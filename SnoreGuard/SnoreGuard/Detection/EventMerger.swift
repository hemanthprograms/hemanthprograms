import Foundation

/// Turns classified windows into snore events.
///
/// A window counts as snoring when its confidence is at least `threshold`. Snoring windows
/// whose gap to the current event is under `maxGap` extend it; events shorter than
/// `minDuration` are dropped. Feed windows in time order with `add(_:)`, then call `finish()`.
struct EventMerger {
    let threshold: Double
    let maxGap: TimeInterval
    let minDuration: TimeInterval

    /// Closed events that passed the minimum length, in time order.
    private(set) var events: [DetectedEvent] = []
    /// The event still being extended, if any. It may not have reached `minDuration` yet.
    private(set) var openEvent: DetectedEvent?

    init(
        threshold: Double = DetectionConfig.defaultThreshold,
        maxGap: TimeInterval = DetectionConfig.mergeGap,
        minDuration: TimeInterval = DetectionConfig.minimumEventDuration
    ) {
        self.threshold = threshold
        self.maxGap = maxGap
        self.minDuration = minDuration
    }

    /// Events so far, counting the open one once it is long enough.
    var eventCount: Int {
        events.count + ((openEvent?.duration ?? 0) >= minDuration ? 1 : 0)
    }

    /// Adds the next window. Returns `true` when it counts as snoring.
    @discardableResult
    mutating func add(_ window: DetectionWindow) -> Bool {
        guard window.confidence >= threshold else { return false }
        if var current = openEvent, window.start - current.end < maxGap {
            current.duration = max(current.end, window.end) - current.start
            current.peakConfidence = max(current.peakConfidence, window.confidence)
            openEvent = current
        } else {
            closeOpenEvent()
            openEvent = DetectedEvent(start: window.start, duration: window.duration, peakConfidence: window.confidence)
        }
        return true
    }

    /// Closes the open event and returns every kept event.
    @discardableResult
    mutating func finish() -> [DetectedEvent] {
        closeOpenEvent()
        return events
    }

    /// Merges a whole recording's windows in one go. Input order doesn't matter.
    static func merge(
        _ windows: [DetectionWindow],
        threshold: Double = DetectionConfig.defaultThreshold,
        maxGap: TimeInterval = DetectionConfig.mergeGap,
        minDuration: TimeInterval = DetectionConfig.minimumEventDuration
    ) -> [DetectedEvent] {
        var merger = EventMerger(threshold: threshold, maxGap: maxGap, minDuration: minDuration)
        for window in windows.sorted(by: { $0.start < $1.start }) {
            merger.add(window)
        }
        return merger.finish()
    }

    private mutating func closeOpenEvent() {
        if let current = openEvent, current.duration >= minDuration {
            events.append(current)
        }
        openEvent = nil
    }
}
