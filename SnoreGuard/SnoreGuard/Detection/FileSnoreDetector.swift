import AVFoundation
import Foundation

/// Runs the same classifier pipeline over an audio file instead of the microphone.
/// Used for the bundled sample, imported recordings, the Simulator and unit tests.
/// Analysis runs as fast as the classifier allows, not in real time.
final class FileSnoreDetector: SnoreDetecting, @unchecked Sendable {
    let url: URL

    private let queue = DispatchQueue(label: "com.hemanthprograms.snoreguard.file-analysis", qos: .userInitiated)
    private let lock = NSLock()
    private var analysedDuration: TimeInterval = 0
    private var isCancelled = false

    private static let chunkSize: AVAudioFrameCount = 16_384

    init(url: URL) {
        self.url = url
    }

    var listenedDuration: TimeInterval {
        lock.withLock { analysedDuration }
    }

    func start() throws -> AsyncThrowingStream<DetectorEvent, Error> {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate > 0, file.length > 0 else { throw SnoreDetectorError.unreadableFile }

        let (stream, continuation) = AsyncThrowingStream<DetectorEvent, Error>.makeStream()
        lock.withLock {
            isCancelled = false
            analysedDuration = 0
        }
        queue.async { [self] in
            do {
                let pipeline = try SoundClassifierPipeline(
                    format: format,
                    timeOffset: 0,
                    onWindow: { window in continuation.yield(.window(window)) },
                    onError: { error in continuation.finish(throwing: error) }
                )
                while file.framePosition < file.length, !lock.withLock({ isCancelled }) {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.chunkSize) else {
                        throw SnoreDetectorError.unreadableFile
                    }
                    try file.read(into: buffer, frameCount: Self.chunkSize)
                    if buffer.frameLength == 0 { break }
                    pipeline.analyze(buffer)
                    let position = Double(file.framePosition) / format.sampleRate
                    lock.withLock { analysedDuration = position }
                }
                pipeline.finish()
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    func stop() {
        lock.withLock { isCancelled = true }
    }
}
