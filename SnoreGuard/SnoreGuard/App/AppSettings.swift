import Foundation

enum SettingsKey {
    static let hasOnboarded = "hasOnboarded"
    static let saveClips = "saveClips"
    static let sensitivity = "sensitivity"
    static let demoMode = "demoMode"
    static let demoDefaultApplied = "demoDefaultApplied"
}

/// How readily a window is counted as snoring.
enum Sensitivity: String, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }

    /// Minimum "snoring" confidence for a window to count.
    var threshold: Double {
        switch self {
        case .low: 0.7
        case .normal: DetectionConfig.defaultThreshold
        case .high: 0.5
        }
    }
}

enum Disclaimer {
    static let text = "SnoreGuard is a wellness tool, not a medical device. If you're worried about your sleep or breathing, talk to a doctor."
}
