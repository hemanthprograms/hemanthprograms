import Foundation

/// Bridges stored nights to the pure `RemedyAnalyzer` input.
enum ResultsBuilder {
    /// One `RemedySamples` per remedy that has at least one counted night, in remedy order.
    static func samples(nights: [Night], remedies: [Remedy]) -> [RemedySamples] {
        var valuesByRemedy: [UUID: [Double]] = [:]
        for night in nights where night.countsTowardResults {
            guard let remedy = night.remedy else { continue }
            valuesByRemedy[remedy.id, default: []].append(night.snoreMinutesPerHour)
        }
        return remedies.compactMap { remedy in
            guard let values = valuesByRemedy[remedy.id] else { return nil }
            return RemedySamples(
                remedyID: remedy.id,
                name: remedy.name,
                phrase: remedy.phrase,
                symbol: remedy.symbol,
                isBaseline: remedy.isBaseline,
                values: values
            )
        }
    }

    static func report(nights: [Night], remedies: [Remedy]) -> RemedyReport {
        RemedyAnalyzer().report(for: samples(nights: nights, remedies: remedies))
    }
}
