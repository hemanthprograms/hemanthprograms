import AVFoundation
import SoundAnalysis

/// One run of Apple's built-in sound classifier over a continuous stream of buffers.
/// Both detectors push audio through this type, so live and file analysis behave the same.
///
/// Not thread-safe: call `analyze(_:)` and `finish()` from one serial queue.
final class SoundClassifierPipeline {
    private let analyzer: SNAudioStreamAnalyzer
    private let observer: SnoringResultsObserver
    private var framePosition: AVAudioFramePosition = 0

    /// - Parameters:
    ///   - timeOffset: Added to every window's start, for streams that begin mid-recording
    ///     (the live detector starts a new pipeline after each interruption).
    ///   - onWindow: Called on the analysing queue for every classified window.
    ///   - onError: Called if the classifier fails.
    init(
        format: AVAudioFormat,
        timeOffset: TimeInterval,
        onWindow: @escaping (DetectionWindow) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = Self.windowDuration(closestTo: DetectionConfig.windowDuration, allowedBy: request.windowDurationConstraint)
        request.overlapFactor = DetectionConfig.windowOverlap
        analyzer = SNAudioStreamAnalyzer(format: format)
        observer = SnoringResultsObserver(timeOffset: timeOffset, onWindow: onWindow, onError: onError)
        try analyzer.add(request, withObserver: observer)
    }

    func analyze(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        analyzer.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
    }

    /// Delivers the remaining windows. Don't analyse more buffers afterwards.
    func finish() {
        analyzer.completeAnalysis()
    }

    /// The allowed window duration closest to `seconds`.
    static func windowDuration(closestTo seconds: TimeInterval, allowedBy constraint: SNTimeDurationConstraint) -> CMTime {
        let preferred = CMTime(seconds: seconds, preferredTimescale: 1_000)
        if constraint.type == .enumerated {
            let options = constraint.enumeratedDurations.map(\.timeValue)
            return options.min { abs($0.seconds - seconds) < abs($1.seconds - seconds) } ?? preferred
        }
        let lower = constraint.durationRange.start.seconds
        let upper = constraint.durationRange.end.seconds
        guard lower.isFinite, upper.isFinite, upper >= lower else { return preferred }
        return CMTime(seconds: min(max(seconds, lower), upper), preferredTimescale: 1_000)
    }
}

private final class SnoringResultsObserver: NSObject, SNResultsObserving {
    private let timeOffset: TimeInterval
    private let onWindow: (DetectionWindow) -> Void
    private let onError: (Error) -> Void

    init(timeOffset: TimeInterval, onWindow: @escaping (DetectionWindow) -> Void, onError: @escaping (Error) -> Void) {
        self.timeOffset = timeOffset
        self.onWindow = onWindow
        self.onError = onError
        super.init()
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let start = result.timeRange.start.seconds
        let duration = result.timeRange.duration.seconds
        guard start.isFinite, duration.isFinite else { return }
        let confidence = result.classification(forIdentifier: DetectionConfig.snoringLabel)?.confidence ?? 0
        onWindow(DetectionWindow(start: timeOffset + start, duration: duration, confidence: confidence))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        onError(error)
    }
}
