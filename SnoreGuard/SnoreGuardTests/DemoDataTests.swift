import SwiftData
import XCTest
@testable import SnoreGuard

/// The demo has to tell the story it was designed for, or the screens won't show every state.
final class DemoDataTests: XCTestCase {
    func testDemoSeedsTwelveNightsWithTheIntendedOutcomes() throws {
        let context = try TestStore.makeContext()
        RemedyCatalog.seedBuiltIns(in: context)
        DemoData.seed(in: context, now: Date(timeIntervalSince1970: 1_761_120_000))

        let nights = try context.fetch(FetchDescriptor<Night>())
        let remedies = RemedyCatalog.allRemedies(in: context)
        XCTAssertEqual(nights.count, 12)
        XCTAssertTrue(nights.allSatisfy { $0.isDemo && $0.countsTowardResults && $0.eventCount > 20 })

        // Stored totals match the targets they were generated from.
        for spec in DemoData.specs {
            let night = try XCTUnwrap(nights.first { abs($0.snoreMinutesPerHour - spec.perHour) < 0.05 })
            XCTAssertEqual(night.remedy?.key, spec.remedyKey)
        }

        // Events never overlap or sit closer than the merge gap.
        for night in nights {
            let events = night.sortedEvents
            for (earlier, later) in zip(events, events.dropFirst()) {
                XCTAssertGreaterThanOrEqual(later.startDate.timeIntervalSince(earlier.endDate), DetectionConfig.mergeGap)
            }
        }

        let report = ResultsBuilder.report(nights: nights, remedies: remedies)
        func label(_ key: String) -> EffectLabel? {
            report.remedies.first { comparison in remedies.first { $0.id == comparison.remedyID }?.key == key }?.label
        }
        XCTAssertEqual(report.baseline?.nights, 4)
        XCTAssertEqual(label("side"), .likelyHelps)
        XCTAssertEqual(label("nasal-strip"), .mightHelp)
        XCTAssertEqual(label("extra-pillow"), .notEnoughData(remedyNightsNeeded: 2, baselineNightsNeeded: 0))
        XCTAssertEqual(report.summary, "Sleeping on your side cut your snoring by about 40% over 4 nights.")

        let plans = try context.fetch(FetchDescriptor<Plan>())
        let plan = try XCTUnwrap(PlanEngine.activePlan(in: plans, demoMode: true))
        let progress = PlanEngine.progress(for: plan, nights: nights)
        XCTAssertEqual(progress.currentNight, 11)
        XCTAssertEqual(progress.totalNights, 12)
        XCTAssertEqual(progress.suggestedRemedyID, RemedyCatalog.remedy(withKey: "extra-pillow", in: context)?.id)
    }

    func testRemovingDemoDataKeepsRealNights() throws {
        let context = try TestStore.makeContext()
        RemedyCatalog.seedBuiltIns(in: context)
        let real = Night(startDate: .now, threshold: 0.6, source: .microphone)
        context.insert(real)
        DemoData.seed(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Night>()), 13)

        DemoData.remove(from: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Night>()).map(\.id), [real.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plan>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SnoreEvent>()), 0)
    }

    func testSeedingTwiceDoesNotDuplicate() throws {
        let context = try TestStore.makeContext()
        DemoData.seed(in: context)
        DemoData.seed(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Night>()), 12)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Plan>()), 1)
        XCTAssertEqual(RemedyCatalog.allRemedies(in: context).count, RemedyCatalog.builtIns.count)
    }
}
