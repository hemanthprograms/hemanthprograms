import SwiftData
import XCTest
@testable import SnoreGuard

final class PlanEngineTests: XCTestCase {
    private let baseline = UUID()
    private let side = UUID()
    private let strip = UUID()
    private let pillow = UUID()

    func testFreshPlan() {
        let progress = PlanEngine.progress(stepRemedyIDs: [baseline, side, strip, pillow], nightsPerStep: 3, nightCounts: [:])
        XCTAssertEqual(progress.totalNights, 12)
        XCTAssertEqual(progress.currentNight, 1)
        XCTAssertEqual(progress.suggestedRemedyID, baseline)
        XCTAssertFalse(progress.isComplete)
    }

    func testExtraNightsDoNotCountTwice() {
        let progress = PlanEngine.progress(
            stepRemedyIDs: [baseline, side, strip, pillow],
            nightsPerStep: 3,
            nightCounts: [baseline: 4, side: 1]
        )
        XCTAssertEqual(progress.completedNights, 4)
        XCTAssertEqual(progress.currentNight, 5)
        XCTAssertEqual(progress.suggestedRemedyID, side)
    }

    func testOffPlanNightsCountTowardTheirOwnStep() {
        // The user tried the nasal strip early; the plan still asks for side sleeping next.
        let progress = PlanEngine.progress(
            stepRemedyIDs: [baseline, side, strip],
            nightsPerStep: 3,
            nightCounts: [baseline: 3, strip: 2]
        )
        XCTAssertEqual(progress.currentNight, 6)
        XCTAssertEqual(progress.suggestedRemedyID, side)
    }

    func testCompletedPlan() {
        let progress = PlanEngine.progress(stepRemedyIDs: [baseline, side], nightsPerStep: 3, nightCounts: [baseline: 3, side: 5])
        XCTAssertTrue(progress.isComplete)
        XCTAssertNil(progress.suggestedRemedyID)
        XCTAssertEqual(progress.currentNight, 6)
    }

    func testActivePlanPrefersDemoOnlyInDemoMode() throws {
        let context = try TestStore.makeContext()
        let real = PlanEngine.createPlan(testing: [side], baselineID: baseline, in: context, createdAt: Date(timeIntervalSince1970: 100))
        let demo = PlanEngine.createPlan(testing: [strip], baselineID: baseline, in: context, createdAt: Date(timeIntervalSince1970: 50), isDemo: true)
        let plans = [real, demo]

        XCTAssertEqual(PlanEngine.activePlan(in: plans, demoMode: true)?.id, demo.id)
        XCTAssertEqual(PlanEngine.activePlan(in: plans, demoMode: false)?.id, real.id)
    }

    func testCreatePlanPutsBaselineFirstAndCapsRemedies() throws {
        let context = try TestStore.makeContext()
        let plan = PlanEngine.createPlan(testing: [side, strip, pillow, UUID()], baselineID: baseline, in: context)
        XCTAssertEqual(plan.stepRemedyIDs, [baseline, side, strip, pillow])
    }

    func testOnlyCountedNightsSincePlanStartCount() throws {
        let context = try TestStore.makeContext()
        RemedyCatalog.seedBuiltIns(in: context)
        let noRemedy = try XCTUnwrap(RemedyCatalog.remedy(withKey: RemedyCatalog.baselineKey, in: context))
        let planStart = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = PlanEngine.createPlan(testing: [], baselineID: noRemedy.id, in: context, createdAt: planStart)

        func addNight(daysFromStart: Double, hours: Double) {
            let night = Night(startDate: planStart.addingTimeInterval(daysFromStart * 86_400), threshold: 0.6, source: .microphone)
            context.insert(night)
            night.remedy = noRemedy
            night.recordedDuration = hours * 3600
        }
        addNight(daysFromStart: -1, hours: 7)   // before the plan
        addNight(daysFromStart: 1, hours: 7)
        addNight(daysFromStart: 2, hours: 0.2)  // too short
        addNight(daysFromStart: 3, hours: 6)

        let nights = try context.fetch(FetchDescriptor<Night>())
        XCTAssertEqual(PlanEngine.progress(for: plan, nights: nights).completedNights, 2)
    }
}
