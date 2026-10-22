import Foundation

/// Per-night values for one remedy: snore minutes per hour, one entry per counted night.
struct RemedySamples: Equatable {
    var remedyID: UUID
    var name: String
    var phrase: String
    var symbol: String
    var isBaseline: Bool
    var values: [Double]
}

/// How confident we are that a remedy changes snoring, worded for people rather than statisticians.
enum EffectLabel: Equatable {
    case baseline
    case notEnoughData(remedyNightsNeeded: Int, baselineNightsNeeded: Int)
    case likelyHelps
    case mightHelp
    case noClearEffect
    case seemsWorse

    var title: String {
        switch self {
        case .baseline: "Baseline"
        case .notEnoughData: "Not enough data yet"
        case .likelyHelps: "Likely helps"
        case .mightHelp: "Might help"
        case .noClearEffect: "No clear effect"
        case .seemsWorse: "Seems worse"
        }
    }

    /// What's still missing, e.g. "2 more nights with this remedy needed".
    var detail: String? {
        guard case let .notEnoughData(remedy, baseline) = self else { return nil }
        var parts: [String] = []
        if remedy > 0 {
            parts.append("\(remedy) more \(RemedyAnalyzer.nights(remedy)) with this remedy")
        }
        if baseline > 0 {
            parts.append("\(baseline) more baseline \(RemedyAnalyzer.nights(baseline))")
        }
        return parts.joined(separator: " and ") + " needed"
    }

    var hasEnoughData: Bool {
        if case .notEnoughData = self { return false }
        return true
    }

    var nightsNeeded: Int {
        if case let .notEnoughData(remedy, baseline) = self { return remedy + baseline }
        return 0
    }

    /// Sort order on the results screen: clearest wins first.
    var rank: Int {
        switch self {
        case .likelyHelps: 0
        case .mightHelp: 1
        case .noClearEffect: 2
        case .seemsWorse: 3
        case .notEnoughData: 4
        case .baseline: 5
        }
    }
}

struct RemedyComparison: Identifiable, Equatable {
    let remedyID: UUID
    let name: String
    let phrase: String
    let symbol: String
    let isBaseline: Bool
    let nights: Int
    let mean: Double
    let standardDeviation: Double
    /// Relative change against the baseline mean, e.g. −0.35 for 35% less snoring.
    let percentChange: Double?
    let pValue: Double?
    let label: EffectLabel

    var id: UUID { remedyID }
}

struct RemedyReport: Equatable {
    let baseline: RemedyComparison?
    /// Every remedy except the baseline, clearest wins first.
    let remedies: [RemedyComparison]
    let summary: String

    var all: [RemedyComparison] { (baseline.map { [$0] } ?? []) + remedies }
    var isEmpty: Bool { baseline == nil && remedies.isEmpty }
}

/// Compares each remedy's nights against the baseline nights. Pure and deterministic.
struct RemedyAnalyzer {
    static let minimumNights = 3
    static let likelyHelpsReduction = 0.20
    static let mightHelpReduction = 0.10
    static let seemsWorseIncrease = 0.10
    static let significanceLevel = 0.10

    var exactEnumerationLimit = 20_000
    var monteCarloIterations = 10_000
    var seed: UInt64 = 0x5EED

    struct Verdict: Equatable {
        let label: EffectLabel
        let percentChange: Double?
        let pValue: Double?
    }

    /// - "Not enough data yet" until both groups have `minimumNights` nights.
    /// - "Likely helps": at least 20% less snoring and a one-sided permutation p-value under 0.1.
    /// - "Might help": at least 10% less snoring.
    /// - "Seems worse": at least 10% more snoring.
    /// - "No clear effect": anything in between.
    func verdict(baseline: [Double], remedy: [Double]) -> Verdict {
        let baselineMean = Statistics.mean(baseline)
        let remedyMean = Statistics.mean(remedy)
        let change: Double? = (baseline.isEmpty || remedy.isEmpty || baselineMean <= 0)
            ? nil
            : (remedyMean - baselineMean) / baselineMean

        let remedyNeeded = max(0, Self.minimumNights - remedy.count)
        let baselineNeeded = max(0, Self.minimumNights - baseline.count)
        if remedyNeeded > 0 || baselineNeeded > 0 {
            return Verdict(
                label: .notEnoughData(remedyNightsNeeded: remedyNeeded, baselineNightsNeeded: baselineNeeded),
                percentChange: change,
                pValue: nil
            )
        }

        let pValue = Statistics.oneSidedPermutationPValue(
            treatment: remedy,
            control: baseline,
            exactLimit: exactEnumerationLimit,
            iterations: monteCarloIterations,
            seed: seed
        )
        guard let change else {
            // The baseline nights had no snoring at all, so there is nothing to reduce.
            return Verdict(label: remedyMean > 0 ? .seemsWorse : .noClearEffect, percentChange: nil, pValue: pValue)
        }

        let tolerance = 1e-9
        let reduction = -change
        let label: EffectLabel
        if reduction >= Self.likelyHelpsReduction - tolerance && pValue < Self.significanceLevel {
            label = .likelyHelps
        } else if reduction >= Self.mightHelpReduction - tolerance {
            label = .mightHelp
        } else if change >= Self.seemsWorseIncrease - tolerance {
            label = .seemsWorse
        } else {
            label = .noClearEffect
        }
        return Verdict(label: label, percentChange: change, pValue: pValue)
    }

    func report(for samples: [RemedySamples]) -> RemedyReport {
        let baselineSamples = samples.first { $0.isBaseline && !$0.values.isEmpty }
        let baselineValues = baselineSamples?.values ?? []
        let baseline = baselineSamples.map { group in
            RemedyComparison(
                remedyID: group.remedyID,
                name: group.name,
                phrase: group.phrase,
                symbol: group.symbol,
                isBaseline: true,
                nights: group.values.count,
                mean: Statistics.mean(group.values),
                standardDeviation: Statistics.standardDeviation(group.values),
                percentChange: nil,
                pValue: nil,
                label: .baseline
            )
        }
        let remedies = samples
            .filter { !$0.isBaseline && !$0.values.isEmpty }
            .map { group in
                let outcome = verdict(baseline: baselineValues, remedy: group.values)
                return RemedyComparison(
                    remedyID: group.remedyID,
                    name: group.name,
                    phrase: group.phrase,
                    symbol: group.symbol,
                    isBaseline: false,
                    nights: group.values.count,
                    mean: Statistics.mean(group.values),
                    standardDeviation: Statistics.standardDeviation(group.values),
                    percentChange: outcome.percentChange,
                    pValue: outcome.pValue,
                    label: outcome.label
                )
            }
            .sorted { lhs, rhs in
                lhs.label.rank != rhs.label.rank ? lhs.label.rank < rhs.label.rank : lhs.mean < rhs.mean
            }
        return RemedyReport(baseline: baseline, remedies: remedies, summary: summary(baseline: baseline, remedies: remedies))
    }

    /// The one-sentence takeaway shown at the top of the results screen.
    func summary(baseline: RemedyComparison?, remedies: [RemedyComparison]) -> String {
        guard let baseline else {
            return remedies.isEmpty
                ? "Record your first night to start comparing remedies."
                : "Record \(Self.minimumNights) nights with no remedy so there's a baseline to compare against."
        }
        if baseline.nights < Self.minimumNights {
            let needed = Self.minimumNights - baseline.nights
            return "Record \(needed) more \(Self.nights(needed)) with no remedy to finish your baseline."
        }
        guard !remedies.isEmpty else {
            return "Your baseline is \(Self.oneDecimal(baseline.mean)) snore minutes per hour. Try a remedy next to see if it helps."
        }
        let ready = remedies.filter { $0.label.hasEnoughData }
        guard !ready.isEmpty else {
            let needed = remedies.map(\.label.nightsNeeded).min() ?? 0
            return "Keep going: \(needed) more \(Self.nights(needed)) until your first comparison."
        }
        if let best = ready.filter({ $0.label == .likelyHelps }).min(by: { $0.mean < $1.mean }),
           let change = best.percentChange {
            return "\(best.phrase) cut your snoring by about \(Self.roundedPercent(change))% over \(best.nights) nights."
        }
        if let best = ready.filter({ $0.label == .mightHelp }).min(by: { $0.mean < $1.mean }),
           let change = best.percentChange {
            return "\(best.phrase) might help: about \(Self.roundedPercent(change))% less snoring over \(best.nights) nights, but it's too early to be sure."
        }
        if ready.allSatisfy({ $0.label == .seemsWorse }) {
            return "No remedy has helped so far. You snored more on remedy nights than on baseline nights."
        }
        return "None of the remedies you've tried has made a clear difference yet."
    }

    /// "About" numbers: nearest 5% from 10% up, nearest 1% below that.
    static func roundedPercent(_ change: Double) -> Int {
        let percent = abs(change) * 100
        return percent >= 10 ? Int((percent / 5).rounded()) * 5 : Int(percent.rounded())
    }

    static func nights(_ count: Int) -> String {
        count == 1 ? "night" : "nights"
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
