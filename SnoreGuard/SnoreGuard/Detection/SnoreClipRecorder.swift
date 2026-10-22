import AVFoundation
import Foundation

/// Keeps the last few seconds of microphone audio in memory so a clip can be saved after the
/// classifier flags snoring. Nothing reaches disk unless `saveClip(to:)` is called, which only
/// happens when the user has turned on "Save snore clips".
final class SnoreClipRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hemanthprograms.snoreguard.clips", qos: .utility)
    private let duration: TimeInterval
    // Ring buffer state, only touched on `queue`.
    private var ring: [Float] = []
    private var writeIndex = 0
    private var filled = 0
    private var sampleRate: Double = 0

    init(duration: TimeInterval = DetectionConfig.clipDuration) {
        self.duration = duration
    }

    /// Copies the buffer's first channel into the ring. Call with every captured buffer.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let rate = buffer.format.sampleRate
        queue.async { self.store(samples, sampleRate: rate) }
    }

    /// Writes the buffered audio (up to `duration` seconds) to `url` as AAC.
    func saveClip(to url: URL) {
        queue.async {
            Self.write(self.orderedSamples(), sampleRate: self.sampleRate, to: url)
        }
    }

    private func store(_ samples: [Float], sampleRate rate: Double) {
        if rate != sampleRate || ring.isEmpty {
            sampleRate = rate
            ring = Array(repeating: 0, count: max(1, Int(rate * duration)))
            writeIndex = 0
            filled = 0
        }
        for sample in samples {
            ring[writeIndex] = sample
            writeIndex = (writeIndex + 1) % ring.count
        }
        filled = min(ring.count, filled + samples.count)
    }

    private func orderedSamples() -> [Float] {
        guard filled > 0 else { return [] }
        if filled < ring.count {
            return Array(ring[0..<filled])
        }
        return Array(ring[writeIndex...] + ring[..<writeIndex])
    }

    @discardableResult
    static func write(_ samples: [Float], sampleRate: Double, to url: URL) -> Bool {
        guard !samples.isEmpty, sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let destination = buffer.floatChannelData?[0] else { return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            destination.update(from: base, count: samples.count)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }
}
