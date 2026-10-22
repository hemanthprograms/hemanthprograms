import Foundation
import SwiftData

/// A stretch of snoring: consecutive snoring windows merged together.
@Model
final class SnoreEvent {
    var startDate: Date = Date()
    var duration: TimeInterval = 0
    var peakConfidence: Double = 0
    /// File name of a saved 10-second clip, only when "Save snore clips" was on.
    var clipFileName: String?
    var night: Night?

    init(startDate: Date, duration: TimeInterval, peakConfidence: Double, clipFileName: String? = nil) {
        self.startDate = startDate
        self.duration = duration
        self.peakConfidence = peakConfidence
        self.clipFileName = clipFileName
    }

    var endDate: Date { startDate.addingTimeInterval(duration) }
}
