import Foundation

/// Exports every night and event as two CSV files for the share sheet.
enum CSVExporter {
    static func nightsCSV(_ nights: [Night]) -> String {
        var rows = [[
            "night_id", "start", "end", "remedy", "recorded_hours", "snore_minutes",
            "snore_minutes_per_hour", "events", "threshold", "source", "counts_toward_results", "demo",
        ]]
        for night in nights.sorted(by: { $0.startDate < $1.startDate }) {
            rows.append([
                night.id.uuidString,
                night.startDate.formatted(.iso8601),
                night.endDate.formatted(.iso8601),
                night.remedy?.name ?? "",
                String(format: "%.2f", night.recordedDuration / 3600),
                String(format: "%.2f", night.totalSnoreMinutes),
                String(format: "%.2f", night.snoreMinutesPerHour),
                String(night.eventCount),
                String(format: "%.2f", night.threshold),
                night.source.rawValue,
                night.countsTowardResults ? "yes" : "no",
                night.isDemo ? "yes" : "no",
            ])
        }
        return csv(rows)
    }

    static func eventsCSV(_ nights: [Night]) -> String {
        var rows = [["night_id", "event_start", "duration_seconds", "peak_confidence"]]
        for night in nights.sorted(by: { $0.startDate < $1.startDate }) {
            for event in night.sortedEvents {
                rows.append([
                    night.id.uuidString,
                    event.startDate.formatted(.iso8601),
                    String(format: "%.1f", event.duration),
                    String(format: "%.3f", event.peakConfidence),
                ])
            }
        }
        return csv(rows)
    }

    /// Writes both files to a temporary folder and returns their URLs.
    static func writeExport(nights: [Night]) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SnoreGuard Export", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let nightsURL = folder.appending(path: "snoreguard-nights.csv", directoryHint: .notDirectory)
        let eventsURL = folder.appending(path: "snoreguard-events.csv", directoryHint: .notDirectory)
        try nightsCSV(nights).write(to: nightsURL, atomically: true, encoding: .utf8)
        try eventsCSV(nights).write(to: eventsURL, atomically: true, encoding: .utf8)
        return [nightsURL, eventsURL]
    }

    /// Quotes a field when it contains a comma, quote or line break (RFC 4180).
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func csv(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }
}
