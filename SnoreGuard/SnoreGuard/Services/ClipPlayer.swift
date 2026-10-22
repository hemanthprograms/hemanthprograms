import AVFoundation
import Observation

/// Plays saved snore clips on the night detail screen.
@Observable
final class ClipPlayer {
    private(set) var playingFileName: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    private let delegate = Delegate()

    init() {
        delegate.onFinish = { [weak self] in
            self?.playingFileName = nil
        }
    }

    func toggle(_ fileName: String) {
        if playingFileName == fileName {
            stop()
            return
        }
        stop()
        guard let url = ClipStore.existingURL(for: fileName) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = delegate
            player.play()
            self.player = player
            playingFileName = fileName
        } catch {
            playingFileName = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingFileName = nil
    }

    private final class Delegate: NSObject, AVAudioPlayerDelegate {
        var onFinish: (() -> Void)?

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish?()
        }
    }
}
