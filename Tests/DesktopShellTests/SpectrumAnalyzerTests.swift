import Foundation
import Testing
@testable import DesktopShell

struct SpectrumAnalyzerTests {
    private func sine(rate: Double = 48000, frequency: Double = 1000, amplitude: Double = 0.5,
                      frames: Int = 48000, offset: Int = 0) -> [Float] {
        (0..<frames).map { Float(amplitude * sin(2 * .pi * frequency * Double($0 + offset) / rate)) }
    }

    private func feed(_ analyzer: SpectrumAnalyzer, _ samples: [Float], channels: Int = 1,
                      chunk: Int = .max) -> [[Double]] {
        samples.withUnsafeBufferPointer { buffer in
            var results: [[Double]] = []
            let total = samples.count / channels
            var offset = 0
            while offset < total {
                let count = min(chunk, total - offset)
                let part = UnsafeBufferPointer(start: buffer.baseAddress!.advanced(by: offset * channels),
                                              count: count * channels)
                results.append(contentsOf: analyzer.process(part, frameCount: count))
                offset += count
            }
            return results
        }
    }

    @Test("13 个对数分段丢掉最低段，48k/44.1k 的频点范围有独立期望值",
          arguments: [48000.0, 44100.0])
    func bandLayout(rate: Double) {
        let analyzer = SpectrumAnalyzer(sampleRate: rate, channels: 1)
        let expectedEdges = [20.0, 33.52529493, 56.19727000, 94.20150254, 157.90665775,
                             264.69336360, 443.69615400, 743.75222103, 1246.72562813,
                             2089.84221879, 3503.12883678, 5872.17137097, 9843.31385363, 16500.0]
        #expect(analyzer.bandEdges.count == 14)
        for (actual, expected) in zip(analyzer.bandEdges, expectedEdges) {
            #expect(abs(actual - expected) < 0.00001)
        }
        let expectedRanges = rate == 48000
            ? [3..<5, 5..<9, 9..<14, 14..<23, 23..<38, 38..<64, 64..<107, 107..<179,
               179..<299, 299..<502, 502..<840, 840..<1408]
            : [4..<6, 6..<9, 9..<15, 15..<25, 25..<42, 42..<70, 70..<116, 116..<195,
               195..<326, 326..<546, 546..<915, 915..<1533]
        #expect(analyzer.bandBinRanges == expectedRanges)
        #expect(analyzer.bandBinRanges.allSatisfy { !$0.isEmpty })
    }

    @Test("空频段取几何中心最近的正频点，越过 Nyquist 时仍有有效范围")
    func emptyBandFallback() {
        var parameters = SpectrumParameters.lano
        parameters.fftSize = 64
        parameters.hop = 32
        let analyzer = SpectrumAnalyzer(sampleRate: 48000, channels: 1, parameters: parameters)
        #expect(analyzer.bandBinRanges[0] == 1..<2)
        #expect(analyzer.bandBinRanges[5] == 1..<2)
        let lowRate = SpectrumAnalyzer(sampleRate: 8000, channels: 1)
        #expect(lowRate.bandBinRanges.allSatisfy { !$0.isEmpty && $0.lowerBound > 0 && $0.upperBound <= 2049 })
        #expect(lowRate.bandBinRanges.last == 2048..<2049)
    }

    @Test("各段中心正弦在补偿前 dB 中以本段为峰值",
          arguments: [48000.0, 44100.0], Array(0..<12))
    func toneLocation(rate: Double, band: Int) throws {
        // Derive the input from the specified log partition, not analyzer helpers.
        let frequency = 20 * pow(825, (Double(band) + 1.5) / 13)
        let analyzer = SpectrumAnalyzer(sampleRate: rate, channels: 1)
        let results = feed(analyzer, sine(rate: rate, frequency: frequency, frames: Int(rate)), chunk: 512)
        #expect(results.count == Int(rate) / 2048)
        let db = analyzer.lastBandDB
        let maximum = try #require(db.max())
        #expect(db[band] == maximum)
        #expect(db.enumerated().allSatisfy { $0.offset == band || $0.element < maximum })
    }

    @Test("满幅 1kHz 正弦的 Hann 频段能量约为 +1.76dB", arguments: [48000.0, 44100.0])
    func normalization(rate: Double) {
        let analyzer = SpectrumAnalyzer(sampleRate: rate, channels: 1)
        _ = feed(analyzer, sine(rate: rate, amplitude: 1, frames: Int(rate)), chunk: 512)
        #expect(abs(analyzer.lastBandDB[6] - 1.7609) < 1)
    }

    @Test("每频点攻放系数与突发正弦的上升衰减")
    func smoothing() throws {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000, channels: 1)
        #expect(abs(analyzer.kAttack - 0.426) < 0.001)
        #expect(abs(analyzer.kDecay - 0.241) < 0.001)
        var rising: [Double] = []
        for hop in 0..<18 {
            let output = feed(analyzer, sine(frequency: 1007.8125, frames: 2048, offset: hop * 2048))
            #expect(output.count == 1)
            rising.append(analyzer.lastBandDB[6])
        }
        let stable = try #require(rising.last)
        #expect(rising[0] < stable - 3)
        #expect(rising[1] > rising[0])
        #expect(abs(rising[7] - stable) < 0.1)
        var previous = stable
        for _ in 0..<8 {
            #expect(feed(analyzer, Array(repeating: 0, count: 2048)).count == 1)
            let current = analyzer.lastBandDB[6]
            #expect(current < previous)
            previous = current
        }
    }

    @Test("初始三秒静音既无输出也无 FFT")
    func initialSilence() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000, channels: 2)
        #expect(analyzer.isSilent)
        #expect(feed(analyzer, Array(repeating: 0, count: 48000 * 3 * 2), channels: 2, chunk: 512).isEmpty)
        #expect(analyzer.isSilent)
        #expect(analyzer.fftCount == 0)
    }

    @Test("连续静音到两秒的首个完整 hop 停止 FFT，恢复清除旧平滑状态")
    func silenceAndResume() throws {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000, channels: 1)
        // About one second, aligned to a hop so the silence boundary is exact.
        #expect(feed(analyzer, sine(frames: 2048 * 24)).count == 24)
        #expect(!analyzer.isSilent)
        let silence = Array<Float>(repeating: 0, count: 2048)
        var previous = analyzer.lastBandDB[6]
        for _ in 0..<46 { // 1.9627 seconds: keep emitting decay.
            let output = feed(analyzer, silence)
            #expect(output.count == 1)
            #expect(!analyzer.isSilent)
            #expect(analyzer.lastBandDB[6] <= previous)
            previous = analyzer.lastBandDB[6]
        }
        let count = analyzer.fftCount
        #expect(feed(analyzer, silence).isEmpty) // 2.0053 seconds: gate this hop.
        #expect(analyzer.isSilent)
        #expect(feed(analyzer, Array(repeating: 0, count: 48000)).isEmpty)
        #expect(analyzer.fftCount == count)
        analyzer.reset() // Reset the partial-hop offset before the restart comparison.
        _ = feed(analyzer, sine(frames: 2048 * 24))
        _ = feed(analyzer, Array(repeating: 0, count: 2048 * 48))
        let resumed = feed(analyzer, sine(frames: 2048))
        let fresh = SpectrumAnalyzer(sampleRate: 48000, channels: 1)
        #expect(resumed == feed(fresh, sine(frames: 2048)))
        #expect(!analyzer.isSilent)

        // With a short gate the previous smoothed bins are still substantial.
        // Restart must erase them, rather than relying on two seconds of decay.
        var parameters = SpectrumParameters.lano
        parameters.silenceSeconds = 4096.0 / 48000
        let shortGate = SpectrumAnalyzer(sampleRate: 48000, channels: 1, parameters: parameters)
        _ = feed(shortGate, sine(frames: 2048 * 24))
        _ = feed(shortGate, Array(repeating: 0, count: 4096))
        #expect(shortGate.isSilent)
        let clean = SpectrumAnalyzer(sampleRate: 48000, channels: 1, parameters: parameters)
        #expect(feed(shortGate, sine(frames: 2048)) == feed(clean, sine(frames: 2048)))
    }

    @Test("静音阈值是严格小于且检查一跳内每个新采样")
    func silenceThreshold() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000, channels: 1)
        #expect(feed(analyzer, Array(repeating: Float(0.000099), count: 2048)).isEmpty)
        var samples = Array<Float>(repeating: 0, count: 2048)
        samples[17] = -SpectrumParameters.lano.silenceThreshold
        #expect(feed(analyzer, samples).count == 1)
        #expect(!analyzer.isSilent)
    }

    @Test("整段、512 帧与不齐 hop 的分块结果逐元素完全相同")
    func chunkIndependence() {
        let signal = sine(frames: 48000) + Array<Float>(repeating: 0, count: 48000 * 3) + sine(frames: 12345)
        let whole = feed(SpectrumAnalyzer(sampleRate: 48000, channels: 1), signal)
        for chunk in [512, 137, 4097] {
            let split = feed(SpectrumAnalyzer(sampleRate: 48000, channels: 1), signal, chunk: chunk)
            #expect(split == whole)
        }
    }

    @Test("多声道逐样本平均，双声道相同等同单声道、反相相消")
    func channels() {
        let mono = sine()
        let expected = feed(SpectrumAnalyzer(sampleRate: 48000, channels: 1), mono)
        let stereo = mono.flatMap { [$0, $0] }
        #expect(feed(SpectrumAnalyzer(sampleRate: 48000, channels: 2), stereo, channels: 2, chunk: 512) == expected)
        let opposite = mono.flatMap { [$0, -$0] }
        let canceled = SpectrumAnalyzer(sampleRate: 48000, channels: 2)
        #expect(feed(canceled, opposite, channels: 2).isEmpty)
        #expect(canceled.isSilent)
        let three = mono.flatMap { [$0, Float(0), -$0] }
        #expect(feed(SpectrumAnalyzer(sampleRate: 48000, channels: 3), three, channels: 3).isEmpty)
    }

    @Test("NaN 和正负无穷逐声道按零处理，后续声音仍能输出")
    func nonfiniteInput() {
        var signal = sine().flatMap { [$0, $0] }
        signal[0] = .nan; signal[130] = .infinity; signal[4117] = -.infinity
        let sanitized = signal.map { $0.isFinite ? $0 : 0 }
        let analyzer = SpectrumAnalyzer(sampleRate: 48000, channels: 2)
        let output = feed(analyzer, signal, channels: 2, chunk: 512)
        #expect(output == feed(SpectrumAnalyzer(sampleRate: 48000, channels: 2), sanitized, channels: 2, chunk: 512))
        #expect(output.count == 23)
        #expect(output.allSatisfy { $0.allSatisfy(\.isFinite) })
        #expect(feed(analyzer, sine().flatMap { [$0, $0] }, channels: 2).count > 0)
    }

    @Test("固定种子的满幅白噪声输出 12 个有限的 0–1 数")
    func outputRange() {
        var seed: UInt64 = 0x51ec7
        let noise: [Float] = (0..<96000).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(seed >> 32) / Double(UInt32.max) * 2 - 1)
        }
        let result = feed(SpectrumAnalyzer(sampleRate: 48000, channels: 1), noise, chunk: 512)
        #expect(result.count == 46)
        #expect(result.allSatisfy { $0.count == 12 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } })
    }

    @Test("倾斜补偿、dB 映射和相邻平均（首尾以自身补齐）", arguments: [43.0, 1000.0, 12000.0])
    func mappingAndNeighbors(frequency: Double) throws {
        var rawParameters = SpectrumParameters.lano
        rawParameters.neighborAverage = false
        let rawAnalyzer = SpectrumAnalyzer(sampleRate: 48000, channels: 1, parameters: rawParameters)
        let signal = sine(frequency: frequency, amplitude: frequency < 100 ? 0.05 : 0.01)
        let raw = try #require(feed(rawAnalyzer, signal).last)
        let db = rawAnalyzer.lastBandDB
        let expected = db.enumerated().map { band, value in
            min(1, max(0, (value + 3 * Double(band - 6) + 49) / 35))
        }
        #expect(raw == expected)
        let activeBand = frequency < 100 ? 0 : frequency > 10000 ? 11 : 6
        #expect(raw[activeBand] > 0 && raw[activeBand] < 1)
        let smooth = try #require(feed(SpectrumAnalyzer(sampleRate: 48000, channels: 1), signal).last)
        #expect(smooth[0] == (raw[0] + raw[0] + raw[1]) / 3)
        #expect(smooth[11] == (raw[10] + raw[11] + raw[11]) / 3)
        for band in 1..<11 { #expect(smooth[band] == (raw[band - 1] + raw[band] + raw[band + 1]) / 3) }
    }

    @Test("reset 清空环形缓冲、部分 hop、静音状态与平滑")
    func reset() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000, channels: 1)
        _ = feed(analyzer, sine(frames: 5000))
        #expect(!analyzer.isSilent)
        analyzer.reset()
        #expect(analyzer.isSilent)
        #expect(analyzer.fftCount == 0)
        let signal = sine(frames: 17000)
        #expect(feed(analyzer, signal, chunk: 512) == feed(SpectrumAnalyzer(sampleRate: 48000, channels: 1), signal))
    }

    @Test("零帧和不足一跳不会提前输出，只消费 frameCount 指定的帧")
    func partialInput() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48000, channels: 1)
        #expect(analyzer.process(UnsafeBufferPointer(start: nil, count: 0), frameCount: 0).isEmpty)
        let signal = sine(frames: 4096)
        let first = signal.withUnsafeBufferPointer { analyzer.process($0, frameCount: 2047) }
        #expect(first.isEmpty)
        #expect(analyzer.fftCount == 0)
        let last = [signal[2047]].withUnsafeBufferPointer { analyzer.process($0, frameCount: 1) }
        #expect(last.count == 1)
        #expect(last == feed(SpectrumAnalyzer(sampleRate: 48000, channels: 1), Array(signal.prefix(2048))))
    }
}
