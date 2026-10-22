import Foundation
import SwiftData

enum NightSource: String {
    case microphone
    case file
    case demo
}

/// One recorded night. Only the measurements are stored, never audio buffers.
@Model
final class Night {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date = Date()
    /// Seconds the microphone was actually listening (excludes interruptions such as calls).
    var recordedDuration: TimeInterval = 0
    var totalSnoreMinutes: Double = 0
    /// The main metric: snore minutes per hour of recording.
    var snoreMinutesPerHour: Double = 0
    var eventCount: Int = 0
    /// Confidence threshold the night was recorded with.
    var threshold: Double = 0.6
    var sourceRaw: String = "microphone"
    var isDemo: Bool = false
    /// True while the night is still being recorded (it is checkpointed every few minutes).
    var isInProgress: Bool = false
    /// True when the app stopped unexpectedly and the night was restored from its last checkpoint.
    var wasRecovered: Bool = false
    var remedy: Remedy?

    @Relationship(deleteRule: .cascade, inverse: \SnoreEvent.night)
    var events: [SnoreEvent] = []

    init(startDate: Date, threshold: Double, source: NightSource, isDemo: Bool = false) {
        self.startDate = startDate
        self.endDate = startDate
        self.threshold = threshold
        self.sourceRaw = source.rawValue
        self.isDemo = isDemo
    }

    var source: NightSource { NightSource(rawValue: sourceRaw) ?? .microphone }

    /// Short recordings would distort per-hour numbers, so they are kept but not compared.
    var countsTowardResults: Bool {
        !isInProgress && recordedDuration >= DetectionConfig.minimumNightDuration
    }

    var sortedEvents: [SnoreEvent] {
        events.sorted { $0.startDate < $1.startDate }
    }

    /// Stores a detected event. `event.start` is seconds since `startDate`.
    func addEvent(_ event: DetectedEvent, clipFileName: String? = nil, in context: ModelContext) {
        let snoreEvent = SnoreEvent(
            startDate: startDate.addingTimeInterval(event.start),
            duration: event.duration,
            peakConfidence: event.peakConfidence,
            clipFileName: clipFileName
        )
        context.insert(snoreEvent)
        events.append(snoreEvent)
    }

    /// Recalculates the stored totals from the events and the listening time.
    func recomputeTotals() {
        let totals = NightTotals(eventDurations: events.map(\.duration), recordedDuration: recordedDuration)
        totalSnoreMinutes = totals.snoreMinutes
        snoreMinutesPerHour = totals.snoreMinutesPerHour
        eventCount = totals.eventCount
    }
}
