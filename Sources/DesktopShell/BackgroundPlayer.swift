import AppKit
import AVFoundation

@MainActor
final class BackgroundPlayer {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(videoURL: URL?) {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        if let videoURL {
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: videoURL))
            play()
        }
    }

    func makeVideoView() -> NSView {
        let view: NSView
        if looper != nil {
            view = VideoView(player: player)
        } else {
            view = NSView(frame: .zero)
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
        }
        view.autoresizingMask = [.width, .height]
        return view
    }

    func play() { player.play() }
    func pause() { player.pause() }
}

@MainActor
private final class VideoView: NSView {
    private let player: AVPlayer

    init(player: AVPlayer) {
        self.player = player
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }
}
