import Foundation

/// One classified slice of audio. Times are seconds since the start of the recording.
struct DetectionWindow: Equatable, Sendable {
    var start: TimeInterval
    var duration: TimeInterval
    /// Confidence of the "snoring" label, 0...1.
    var confidence: Double

    var end: TimeInterval { start + duration }
}

/// A merged stretch of snoring. Times are seconds since the start of the recording.
struct DetectedEvent: Equatable, Sendable {
    var start: TimeInterval
    var duration: TimeInterval
    var peakConfidence: Double

    var end: TimeInterval { start + duration }
}

enum DetectorEvent: Sendable {
    case window(DetectionWindow)
    /// Listening stopped temporarily (a call, Siri, another app took the microphone).
    case paused
    /// Listening resumed after a pause.
    case resumed
}

/// A source of classified audio windows: the live microphone or an audio file.
/// Both implementations run the same `SoundClassifierPipeline`.
protocol SnoreDetecting: AnyObject {
    /// Seconds of audio analysed so far.
    var listenedDuration: TimeInterval { get }

    /// Starts listening. The stream finishes when the source runs out (file)
    /// or after `stop()` (live), once the last windows have been delivered.
    func start() throws -> AsyncThrowingStream<DetectorEvent, Error>

    func stop()
}

enum SnoreDetectorError: LocalizedError {
    case microphoneUnavailable
    case alreadyRunning
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            "The microphone isn't available right now."
        case .alreadyRunning:
            "SnoreGuard is already listening."
        case .unreadableFile:
            "That audio file couldn't be read."
        }
    }
}
