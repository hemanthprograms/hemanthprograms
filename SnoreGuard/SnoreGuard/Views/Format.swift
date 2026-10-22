import Foundation

enum Format {
    /// "8.4"
    static func perHour(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// "32"
    static func minutes(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// "−35%", "+12%", "0%"
    static func percentChange(_ change: Double) -> String {
        let value = Int((change * 100).rounded())
        if value == 0 { return "0%" }
        return value > 0 ? "+\(value)%" : "\u{2212}\(abs(value))%"
    }

    /// "7h 12m", "45m", "2m 30s", "40s"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes >= 10 { return "\(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    /// "7 hours, 12 minutes", for VoiceOver.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        var components = DateComponents()
        components.hour = total / 3600
        components.minute = (total % 3600) / 60
        if total < 600 {
            components.second = total % 60
        }
        return DateComponentsFormatter.localizedString(from: components, unitsStyle: .full) ?? duration(seconds)
    }

    /// "2:14:07"
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// "Tuesday, Oct 21"
    static func nightTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "11:04 PM"
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func nights(_ count: Int) -> String {
        "\(count) \(count == 1 ? "night" : "nights")"
    }
}
