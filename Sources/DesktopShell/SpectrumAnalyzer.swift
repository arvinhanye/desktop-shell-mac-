import Foundation
import Accelerate

struct SpectrumParameters: Equatable {
    var fftSize = 4096
    var hop = 2048
    var minHz = 20.0
    var maxHz = 16500.0
    var bandCount = 12
    var attack = 0.100
    var decay = 0.060
    var floorDB = -49.0
    var ceilingDB = -14.0
    var tiltDBPerBand = 3.0
    var tiltPivot = 6
    var neighborAverage = true
    var silenceThreshold: Float = 1e-4
    var silenceSeconds = 2.0
    static let lano = SpectrumParameters()
}

/// Stateful pure computation; use each instance on one queue, never concurrently.
final class SpectrumAnalyzer {
    private let sampleRate: Double
    private let channels: Int
    private let parameters: SpectrumParameters
    private let setup: FFTSetup
    private let log2Size: vDSP_Length
    private let ring: UnsafeMutableBufferPointer<Float>
    private let window: UnsafeMutableBufferPointer<Float>
    private let real: UnsafeMutableBufferPointer<Float>
    private let imaginary: UnsafeMutableBufferPointer<Float>
    private let smoothed: UnsafeMutableBufferPointer<Double>
    private let bandDB: UnsafeMutableBufferPointer<Double>
    private let mapped: UnsafeMutableBufferPointer<Double>
    private var writeIndex = 0
    private var hopFrames = 0
    private var hopPeak: Float = 0
    private var silentHops = 0

    // Read-only diagnostics for deterministic signal tests; snapshots allocate only
    // when requested by a caller, never in the real-time processing path.
    let bandEdges: [Double]
    let bandBinRanges: [Range<Int>]
    let kAttack: Double
    let kDecay: Double
    private(set) var isSilent = true
    private(set) var fftCount = 0
    var lastBandDB: [Double] { Array(bandDB) }

    init(sampleRate: Double, channels: Int, parameters: SpectrumParameters = .lano) {
        let p = parameters
        precondition(sampleRate.isFinite && sampleRate > 0 && channels > 0)
        precondition(p.fftSize >= 2 && p.fftSize.nonzeroBitCount == 1)
        precondition(p.hop > 0 && p.hop <= p.fftSize && p.bandCount > 0)
        precondition(p.minHz.isFinite && p.maxHz.isFinite && p.minHz > 0 && p.maxHz > p.minHz)
        precondition((p.maxHz / p.minHz).isFinite)
        precondition(p.attack.isFinite && p.attack >= 0 && p.decay.isFinite && p.decay >= 0)
        precondition(p.floorDB.isFinite && p.ceilingDB.isFinite && p.ceilingDB > p.floorDB)
        precondition(p.tiltDBPerBand.isFinite)
        precondition(p.silenceThreshold.isFinite && p.silenceThreshold > 0)
        precondition(p.silenceSeconds.isFinite && p.silenceSeconds >= 0)
        self.sampleRate = sampleRate
        self.channels = channels
        self.parameters = p
        log2Size = vDSP_Length(p.fftSize.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else {
            preconditionFailure("SpectrumAnalyzer: FFT setup allocation failed")
        }
        self.setup = setup
        let half = p.fftSize / 2
        ring = Self.allocate(p.fftSize, repeating: Float(0))
        window = Self.allocate(p.fftSize, repeating: Float(0))
        real = Self.allocate(half, repeating: Float(0))
        imaginary = Self.allocate(half, repeating: Float(0))
        smoothed = Self.allocate(half + 1, repeating: 0.0)
        bandDB = Self.allocate(p.bandCount, repeating: -120.0)
        mapped = Self.allocate(p.bandCount, repeating: 0.0)
        // DENORM is the periodic 0.5 * (1 - cos(2πn/N)) Hann, coherent gain 0.5.
        // vDSP_HANN_NORM instead uses 0.81649..., which changes our calibration.
        vDSP_hann_window(window.baseAddress!, vDSP_Length(p.fftSize), Int32(vDSP_HANN_DENORM))
        let hopSeconds = Double(p.hop) / sampleRate
        kAttack = p.attack == 0 ? 0 : exp(-2 * hopSeconds / p.attack)
        kDecay = p.decay == 0 ? 0 : exp(-2 * hopSeconds / p.decay)
        let edges = (0...(p.bandCount + 1)).map {
            p.minHz * pow(p.maxHz / p.minHz, Double($0) / Double(p.bandCount + 1))
        }
        bandEdges = edges
        bandBinRanges = (0..<p.bandCount).map { band in
            let low = edges[band + 1], high = edges[band + 2]
            // Half-open frequency edges; index zero (DC) is deliberately excluded.
            let first = Int(min(Double(half + 1), max(1, ceil(low / sampleRate * Double(p.fftSize)))))
            let end = Int(min(Double(half + 1), max(1, ceil(high / sampleRate * Double(p.fftSize)))))
            if first < end { return first..<end }
            let center = sqrt(low) * sqrt(high)
            let nearest = Int(min(Double(half), max(1, (center / sampleRate * Double(p.fftSize)).rounded())))
            return nearest..<(nearest + 1)
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        for buffer in [ring, window, real, imaginary] { buffer.deinitialize(); buffer.deallocate() }
        for buffer in [smoothed, bandDB, mapped] { buffer.deinitialize(); buffer.deallocate() }
    }

    private static func allocate<T>(_ count: Int, repeating value: T) -> UnsafeMutableBufferPointer<T> {
        let buffer = UnsafeMutableBufferPointer<T>.allocate(capacity: count)
        buffer.initialize(repeating: value)
        return buffer
    }

    /// Interleaved Float32 samples. Initial history is zero-padded; even the first
    /// hop can emit a result. Only the returned arrays allocate during processing.
    func process(_ samples: UnsafeBufferPointer<Float>, frameCount: Int) -> [[Double]] {
        // Division avoids overflowing frameCount * channels during validation.
        precondition(frameCount >= 0 && frameCount <= samples.count / channels)
        var results: [[Double]] = []
        let mask = parameters.fftSize - 1
        for frame in 0..<frameCount {
            var sum = 0.0
            for channel in 0..<channels {
                let value = samples[frame * channels + channel]
                if value.isFinite { sum += Double(value) }
            }
            let mono = Float(sum / Double(channels))
            ring[writeIndex] = mono
            writeIndex = (writeIndex + 1) & mask
            hopPeak = max(hopPeak, abs(mono))
            hopFrames += 1
            if hopFrames != parameters.hop { continue }
            hopFrames = 0
            let quiet = hopPeak < parameters.silenceThreshold
            hopPeak = 0
            if quiet {
                if isSilent { continue }
                silentHops += 1
                if Double(silentHops) * Double(parameters.hop) / sampleRate >= parameters.silenceSeconds {
                    isSilent = true
                    continue
                }
            } else {
                silentHops = 0
                if isSilent {
                    smoothed.update(repeating: 0)
                    isSilent = false
                }
            }
            results.append(analyze())
        }
        return results
    }

    func reset() {
        ring.update(repeating: 0)
        smoothed.update(repeating: 0)
        bandDB.update(repeating: -120)
        mapped.update(repeating: 0)
        writeIndex = 0
        hopFrames = 0
        hopPeak = 0
        silentHops = 0
        isSilent = true
        fftCount = 0
    }

    private func analyze() -> [Double] {
        let n = parameters.fftSize, half = n / 2, mask = n - 1
        // Pack even/odd real samples directly into zrip's split-complex input.
        // writeIndex points to the oldest sample, including initial zero history.
        for i in 0..<half {
            let even = 2 * i, odd = even + 1
            real[i] = ring[(writeIndex + even) & mask] * window[even]
            imaginary[i] = ring[(writeIndex + odd) & mask] * window[odd]
        }
        var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
        vDSP_fft_zrip(setup, &split, 1, log2Size, FFTDirection(FFT_FORWARD))
        fftCount += 1
        // Hann divides by N/4; zrip's factor of two divides once more => 2/N.
        let scale = 2 / Double(n)
        for bin in 1...half {
            // zrip packs the real Nyquist coefficient in imaginary[0], not bin 0.
            let magnitude = bin == half ? abs(Double(imaginary[0]))
                : hypot(Double(real[bin]), Double(imaginary[bin]))
            let value = magnitude * scale
            let old = smoothed[bin]
            let coefficient = value > old ? kAttack : kDecay
            smoothed[bin] = value + coefficient * (old - value)
        }
        for band in 0..<parameters.bandCount {
            var energy = 0.0
            for bin in bandBinRanges[band] { energy += smoothed[bin] * smoothed[bin] }
            let db = 10 * log10(max(energy, 1e-12))
            bandDB[band] = db
            let tilted = db + parameters.tiltDBPerBand * (Double(band) - Double(parameters.tiltPivot))
            mapped[band] = min(1, max(0, (tilted - parameters.floorDB) / (parameters.ceilingDB - parameters.floorDB)))
        }
        var output = Array(repeating: 0.0, count: parameters.bandCount)
        for band in 0..<parameters.bandCount {
            output[band] = parameters.neighborAverage
                ? (mapped[max(0, band - 1)] + mapped[band] + mapped[min(parameters.bandCount - 1, band + 1)]) / 3
                : mapped[band]
        }
        return output
    }
}
