import XCTest
@testable import SnoreGuard

final class RemedyAnalyzerTests: XCTestCase {
    private let analyzer = RemedyAnalyzer()
    private let baselineID = UUID()
    private let sideID = UUID()
    private let stripID = UUID()

    // MARK: - Labels

    func testNotEnoughRemedyNights() {
        let verdict = analyzer.verdict(baseline: [10, 11, 12], remedy: [5, 6])
        XCTAssertEqual(verdict.label, .notEnoughData(remedyNightsNeeded: 1, baselineNightsNeeded: 0))
        XCTAssertNil(verdict.pValue)
        XCTAssertEqual(verdict.percentChange ?? 0, -0.5, accuracy: 1e-9, "Change is still reported for context")
    }

    func testNotEnoughBaselineNights() {
        let verdict = analyzer.verdict(baseline: [10], remedy: [5, 6, 7])
        XCTAssertEqual(verdict.label, .notEnoughData(remedyNightsNeeded: 0, baselineNightsNeeded: 2))
        XCTAssertEqual(verdict.label.nightsNeeded, 2)
        XCTAssertEqual(verdict.label.detail, "2 more baseline nights needed")
    }

    func testNoBaselineAtAll() {
        let verdict = analyzer.verdict(baseline: [], remedy: [5])
        XCTAssertEqual(verdict.label, .notEnoughData(remedyNightsNeeded: 2, baselineNightsNeeded: 3))
        XCTAssertNil(verdict.percentChange)
        XCTAssertEqual(verdict.label.detail, "2 more nights with this remedy and 3 more baseline nights needed")
    }

    func testLikelyHelps() {
        // About 41% less snoring, and every remedy night beat every baseline night (p = 1/20).
        let verdict = analyzer.verdict(baseline: [10, 11, 12], remedy: [6, 7, 6.5])
        XCTAssertEqual(verdict.label, .likelyHelps)
        XCTAssertEqual(verdict.pValue ?? 1, 0.05, accuracy: 1e-9)
        XCTAssertEqual(verdict.percentChange ?? 0, -4.5 / 11, accuracy: 1e-9)
    }

    func testBigDropWithoutEnoughEvidenceIsOnlyMightHelp() {
        // Exactly 20% less on average, but the nights overlap a lot (p = 6/20).
        let verdict = analyzer.verdict(baseline: [10, 14, 6], remedy: [5, 12, 7])
        XCTAssertEqual(verdict.label, .mightHelp)
        XCTAssertEqual(verdict.pValue ?? 0, 0.3, accuracy: 1e-9)
    }

    func testMightHelp() {
        // Consistent but small: 10% less.
        let verdict = analyzer.verdict(baseline: [10, 10, 10], remedy: [8.5, 9, 9.5])
        XCTAssertEqual(verdict.label, .mightHelp)
    }

    func testNoClearEffect() {
        let verdict = analyzer.verdict(baseline: [10, 12, 11], remedy: [10.5, 11.5, 11])
        XCTAssertEqual(verdict.label, .noClearEffect)
        XCTAssertEqual(verdict.percentChange ?? 1, 0, accuracy: 1e-9)
    }

    func testSmallIncreaseIsNoClearEffect() {
        let verdict = analyzer.verdict(baseline: [10, 10, 10], remedy: [10.5, 10.8, 10.2])
        XCTAssertEqual(verdict.label, .noClearEffect)
    }

    func testSeemsWorse() {
        let verdict = analyzer.verdict(baseline: [10, 11, 12], remedy: [13, 14, 12.5])
        XCTAssertEqual(verdict.label, .seemsWorse)
    }

    func testSilentBaselineCannotBeImproved() {
        XCTAssertEqual(analyzer.verdict(baseline: [0, 0, 0], remedy: [0, 0, 0]).label, .noClearEffect)
        XCTAssertEqual(analyzer.verdict(baseline: [0, 0, 0], remedy: [1, 0, 2]).label, .seemsWorse)
    }

    // MARK: - Statistics

    func testExactPermutationPValue() {
        XCTAssertEqual(Statistics.oneSidedPermutationPValue(treatment: [1, 2, 3], control: [10, 11, 12]), 0.05, accuracy: 1e-12)
        XCTAssertEqual(Statistics.oneSidedPermutationPValue(treatment: [10, 11, 12], control: [1, 2, 3]), 1, accuracy: 1e-12)
    }

    func testMonteCarloPermutationIsRepeatable() {
        let control = (0..<20).map { 10 + Double($0 % 5) }
        let treatment = (0..<20).map { 8 + Double($0 % 5) }
        let first = Statistics.oneSidedPermutationPValue(treatment: treatment, control: control, exactLimit: 100, iterations: 2_000)
        let second = Statistics.oneSidedPermutationPValue(treatment: treatment, control: control, exactLimit: 100, iterations: 2_000)
        XCTAssertEqual(first, second)
        XCTAssertLessThan(first, 0.05)
        XCTAssertGreaterThan(first, 0)
    }

    func testMeanAndStandardDeviation() {
        XCTAssertEqual(Statistics.mean([2, 4, 6]), 4)
        XCTAssertEqual(Statistics.mean([]), 0)
        XCTAssertEqual(Statistics.standardDeviation([2, 4, 6]), 2, accuracy: 1e-12)
        XCTAssertEqual(Statistics.standardDeviation([5]), 0)
    }

    func testBinomialAndCombinations() {
        XCTAssertEqual(Statistics.binomial(6, 3, limit: 1_000), 20)
        XCTAssertNil(Statistics.binomial(40, 20, limit: 1_000))
        var count = 0
        Statistics.forEachCombination(n: 6, k: 3) { _ in count += 1 }
        XCTAssertEqual(count, 20)
    }

    // MARK: - Report

    func testReportSummaryNamesTheWinner() {
        let report = analyzer.report(for: [
            samples(baselineID, "No remedy", isBaseline: true, [10, 11, 12]),
            samples(sideID, "Sleep on side", phrase: "Sleeping on your side", [6.5, 6.6, 6.7]),
            samples(stripID, "Nasal strip", [10.4, 10.6, 11]),
        ])

        XCTAssertEqual(report.summary, "Sleeping on your side cut your snoring by about 40% over 3 nights.")
        XCTAssertEqual(report.baseline?.label, .baseline)
        XCTAssertEqual(report.remedies.map(\.remedyID), [sideID, stripID], "Clearest wins first")
        XCTAssertEqual(report.all.first?.remedyID, baselineID)
    }

    func testReportSummaryForMightHelp() {
        let report = analyzer.report(for: [
            samples(baselineID, "No remedy", isBaseline: true, [10, 10, 10]),
            samples(stripID, "Nasal strip", phrase: "A nasal strip", [8.5, 9, 9.5]),
        ])
        XCTAssertEqual(report.summary, "A nasal strip might help: about 10% less snoring over 3 nights, but it's too early to be sure.")
    }

    func testReportSummaryWhenNothingWorks() {
        let report = analyzer.report(for: [
            samples(baselineID, "No remedy", isBaseline: true, [10, 12, 11]),
            samples(stripID, "Nasal strip", [10.5, 11.5, 11]),
        ])
        XCTAssertEqual(report.summary, "None of the remedies you've tried has made a clear difference yet.")
    }

    func testReportSummaryWhileCollectingData() {
        let report = analyzer.report(for: [
            samples(baselineID, "No remedy", isBaseline: true, [10, 12, 11]),
            samples(stripID, "Nasal strip", [9]),
        ])
        XCTAssertEqual(report.summary, "Keep going: 2 more nights until your first comparison.")
    }

    func testReportSummaryWithoutBaseline() {
        let report = analyzer.report(for: [samples(stripID, "Nasal strip", [9, 8, 7])])
        XCTAssertNil(report.baseline)
        XCTAssertEqual(report.summary, "Record 3 nights with no remedy so there's a baseline to compare against.")
    }

    func testReportSummaryWithPartialBaseline() {
        let report = analyzer.report(for: [samples(baselineID, "No remedy", isBaseline: true, [10])])
        XCTAssertEqual(report.summary, "Record 2 more nights with no remedy to finish your baseline.")
    }

    func testEmptyReport() {
        let report = analyzer.report(for: [])
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.summary, "Record your first night to start comparing remedies.")
    }

    func testRoundedPercent() {
        XCTAssertEqual(RemedyAnalyzer.roundedPercent(-0.394), 40)
        XCTAssertEqual(RemedyAnalyzer.roundedPercent(-0.35), 35)
        XCTAssertEqual(RemedyAnalyzer.roundedPercent(-0.07), 7)
    }

    private func samples(_ id: UUID, _ name: String, phrase: String? = nil, isBaseline: Bool = false, _ values: [Double]) -> RemedySamples {
        RemedySamples(remedyID: id, name: name, phrase: phrase ?? name, symbol: "circle", isBaseline: isBaseline, values: values)
    }
}
