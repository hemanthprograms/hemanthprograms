import SwiftData
import XCTest
@testable import SnoreGuard

final class NightMetricsTests: XCTestCase {
    func testPerHourNormalisesByRecordingLength() {
        // 30 minutes of snoring over 6 hours is 5 snore minutes per hour.
        XCTAssertEqual(NightTotals.snoreMinutesPerHour(snoreMinutes: 30, recordedDuration: 6 * 3600), 5, accuracy: 1e-9)
    }

    func testSameSnoringOverALongerNightIsALowerRate() {
        let short = NightTotals.snoreMinutesPerHour(snoreMinutes: 40, recordedDuration: 4 * 3600)
        let long = NightTotals.snoreMinutesPerHour(snoreMinutes: 40, recordedDuration: 8 * 3600)
        XCTAssertEqual(short, 10, accuracy: 1e-9)
        XCTAssertEqual(long, 5, accuracy: 1e-9)
    }

    func testNothingRecordedIsZero() {
        XCTAssertEqual(NightTotals.snoreMinutesPerHour(snoreMinutes: 10, recordedDuration: 0), 0)
    }

    func testRateIsCappedAtSixty() {
        XCTAssertEqual(NightTotals.snoreMinutesPerHour(snoreMinutes: 90, recordedDuration: 3600), 60)
    }

    func testTotalsFromEventDurations() {
        let totals = NightTotals(eventDurations: [30, 90, 60], recordedDuration: 2 * 3600)
        XCTAssertEqual(totals.snoreMinutes, 3, accuracy: 1e-9)
        XCTAssertEqual(totals.snoreMinutesPerHour, 1.5, accuracy: 1e-9)
        XCTAssertEqual(totals.eventCount, 3)
    }

    func testNightRecomputesTotalsFromItsEvents() throws {
        let context = try TestStore.makeContext()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let night = Night(startDate: start, threshold: 0.6, source: .microphone)
        context.insert(night)
        night.addEvent(DetectedEvent(start: 600, duration: 120, peakConfidence: 0.8), in: context)
        night.addEvent(DetectedEvent(start: 3_000, duration: 240, peakConfidence: 0.9), in: context)
        night.recordedDuration = 4 * 3600
        night.recomputeTotals()

        XCTAssertEqual(night.totalSnoreMinutes, 6, accuracy: 1e-9)
        XCTAssertEqual(night.snoreMinutesPerHour, 1.5, accuracy: 1e-9)
        XCTAssertEqual(night.eventCount, 2)
        XCTAssertEqual(night.sortedEvents.first?.startDate, start.addingTimeInterval(600))
    }

    func testShortNightsDoNotCountTowardResults() throws {
        let context = try TestStore.makeContext()
        let night = Night(startDate: .now, threshold: 0.6, source: .file)
        context.insert(night)
        night.recordedDuration = 29 * 60
        XCTAssertFalse(night.countsTowardResults)
        night.recordedDuration = 30 * 60
        XCTAssertTrue(night.countsTowardResults)
        night.isInProgress = true
        XCTAssertFalse(night.countsTowardResults)
    }
}

enum TestStore {
    static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Night.self, SnoreEvent.self, Remedy.self, Plan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        containers.append(container)
        return ModelContext(container)
    }

    /// Keeps containers alive for the duration of the test run.
    private static var containers: [ModelContainer] = []
}
