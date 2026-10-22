import Foundation

/// Tunable constants for the detection pipeline. Change them here and nowhere else.
enum DetectionConfig {
    /// Label of Apple's built-in sound classifier (`SNClassifierIdentifier.version1`) that we read.
    static let snoringLabel = "snoring"
    /// Preferred analysis window, in seconds. Clamped to what the classifier allows.
    static let windowDuration: TimeInterval = 1.5
    /// Overlap between consecutive windows (0.5 means a new window every 0.75 s).
    static let windowOverlap: Double = 0.5
    /// A window counts as snoring when its confidence is at least this. Normal sensitivity.
    static let defaultThreshold: Double = 0.6
    /// Snoring windows separated by less than this many seconds belong to the same event.
    static let mergeGap: TimeInterval = 10
    /// Events shorter than this are dropped.
    static let minimumEventDuration: TimeInterval = 3
    /// Nights with less listening time than this don't count toward results or the plan.
    static let minimumNightDuration: TimeInterval = 30 * 60
    /// Snore clips (only when the user turns them on).
    static let maxClipsPerNight = 10
    static let clipDuration: TimeInterval = 10
    /// How long the "Snoring detected" indicator stays lit after a snoring window.
    static let snoringIndicatorHold: TimeInterval = 4
    /// How often an in-progress night is saved, so an unexpected exit loses little data.
    static let checkpointInterval: TimeInterval = 5 * 60
}
