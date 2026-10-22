import Foundation

/// Per-night numbers derived from events. Normalising by listening time makes a short
/// night and a long night comparable.
struct NightTotals: Equatable {
    let snoreMinutes: Double
    let snoreMinutesPerHour: Double
    let eventCount: Int

    init(eventDurations: [TimeInterval], recordedDuration: TimeInterval) {
        snoreMinutes = eventDurations.reduce(0, +) / 60
        snoreMinutesPerHour = NightTotals.snoreMinutesPerHour(snoreMinutes: snoreMinutes, recordedDuration: recordedDuration)
        eventCount = eventDurations.count
    }

    /// Snore minutes per hour of recording, clamped to 0...60. Zero when nothing was recorded.
    static func snoreMinutesPerHour(snoreMinutes: Double, recordedDuration: TimeInterval) -> Double {
        guard recordedDuration > 0 else { return 0 }
        let rate = snoreMinutes / (recordedDuration / 3600)
        return min(max(rate, 0), 60)
    }
}
