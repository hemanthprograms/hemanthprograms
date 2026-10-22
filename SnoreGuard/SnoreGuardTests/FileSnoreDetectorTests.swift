import AVFoundation
import XCTest
@testable import SnoreGuard

/// Runs the real SoundAnalysis pipeline over audio files, the same path the microphone uses.
final class FileSnoreDetectorTests: XCTestCase {
    private func windows(from url: URL) async throws -> (windows: [DetectionWindow], listened: TimeInterval) {
        let detector = FileSnoreDetector(url: url)
        var windows: [DetectionWindow] = []
        for try await event in try detector.start() {
            if case .window(let window) = event {
                windows.append(window)
            }
        }
        return (windows, detector.listenedDuration)
    }

    func testBundledSampleRunsThroughThePipeline() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "SampleSnoring", withExtension: "m4a"), "Sample recording missing from the app bundle")
        let result = try await windows(from: url)

        XCTAssertEqual(result.listened, 90, accuracy: 1)
        // 90 s at a 0.75 s hop is about 118 windows; allow for the classifier's own framing.
        XCTAssertGreaterThan(result.windows.count, 40)
        XCTAssertEqual(result.windows.first?.duration ?? 0, DetectionConfig.windowDuration, accuracy: 0.25)
        XCTAssertEqual(result.windows.map(\.start), result.windows.map(\.start).sorted(), "Windows arrive in time order")
        XCTAssertTrue(result.windows.allSatisfy { (0...1).contains($0.confidence) })
        XCTAssertLessThanOrEqual(result.windows.last?.end ?? 0, 91)

        let events = EventMerger.merge(result.windows)
        let peak = result.windows.map(\.confidence).max() ?? 0
        print("SampleSnoring.m4a: \(result.windows.count) windows, peak snoring confidence \(String(format: "%.2f", peak)), \(events.count) events")
    }

    func testSteadyToneIsNotSnoring() async throws {
        let url = try makeToneFile(seconds: 12, frequency: 1_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await windows(from: url)

        XCTAssertFalse(result.windows.isEmpty)
        XCTAssertEqual(result.listened, 12, accuracy: 0.5)
        XCTAssertTrue(EventMerger.merge(result.windows).isEmpty)
    }

    func testUnreadableFileThrows() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "not-audio.m4a")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try FileSnoreDetector(url: url).start())
    }

    private func makeToneFile(seconds: Double, frequency: Double) throws -> URL {
        let sampleRate = 16_000.0
        let url = FileManager.default.temporaryDirectory.appending(path: "tone-\(UUID().uuidString).caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frames) {
            samples[index] = Float(0.3 * sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
