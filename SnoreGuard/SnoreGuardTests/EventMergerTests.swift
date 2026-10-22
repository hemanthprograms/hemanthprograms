import XCTest
@testable import SnoreGuard

final class EventMergerTests: XCTestCase {
    /// `count` back-to-back 1.5 s windows with 50% overlap, starting at `start`.
    private func windows(from start: TimeInterval, count: Int, confidence: Double = 0.9) -> [DetectionWindow] {
        (0..<count).map { DetectionWindow(start: start + Double($0) * 0.75, duration: 1.5, confidence: confidence) }
    }

    func testOverlappingWindowsMergeIntoOneEvent() {
        let events = EventMerger.merge(windows(from: 0, count: 5))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].start, 0)
        XCTAssertEqual(events[0].duration, 4.5, accuracy: 1e-9)
    }

    func testGapShorterThanTenSecondsIsMerged() {
        // First run ends at 4.5 s, second starts at 14.4 s: a 9.9 s gap.
        let events = EventMerger.merge(windows(from: 0, count: 5) + windows(from: 14.4, count: 5))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].duration, 18.9, accuracy: 1e-9)
    }

    func testGapOfTenSecondsOrMoreStartsANewEvent() {
        // First run ends at 4.5 s, second starts at 14.5 s: exactly 10 s apart.
        let events = EventMerger.merge(windows(from: 0, count: 5) + windows(from: 14.5, count: 5))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].start, 14.5)
    }

    func testEventsShorterThanThreeSecondsAreDropped() {
        // Two windows span 2.25 s; three span exactly 3 s.
        XCTAssertTrue(EventMerger.merge(windows(from: 0, count: 2)).isEmpty)
        XCTAssertEqual(EventMerger.merge(windows(from: 0, count: 3)).count, 1)
    }

    func testShortBlipBetweenEventsIsDroppedButLongEventsKept() {
        let input = windows(from: 0, count: 6) + windows(from: 30, count: 1) + windows(from: 60, count: 8)
        let events = EventMerger.merge(input)

        XCTAssertEqual(events.map(\.start), [0, 60])
    }

    func testWindowsBelowThresholdAreIgnored() {
        XCTAssertTrue(EventMerger.merge(windows(from: 0, count: 10, confidence: 0.59), threshold: 0.6).isEmpty)
    }

    func testThresholdIsInclusive() {
        XCTAssertEqual(EventMerger.merge(windows(from: 0, count: 4, confidence: 0.6), threshold: 0.6).count, 1)
    }

    func testQuietWindowsInsideAnEventDoNotSplitIt() {
        var input = windows(from: 0, count: 4)
        input += windows(from: 3, count: 4, confidence: 0.1) // 3 s of non-snoring
        input += windows(from: 6, count: 4)
        let events = EventMerger.merge(input)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].duration, 9.75, accuracy: 1e-9) // last snoring window ends at 8.25 + 1.5
    }

    func testPeakConfidenceIsTheHighestWindow() {
        var input = windows(from: 0, count: 5, confidence: 0.7)
        input[2].confidence = 0.95
        XCTAssertEqual(EventMerger.merge(input).first?.peakConfidence, 0.95)
    }

    func testUnsortedInputIsHandled() {
        let input = (windows(from: 0, count: 5) + windows(from: 40, count: 5)).shuffled()
        XCTAssertEqual(EventMerger.merge(input).map(\.start), [0, 40])
    }

    func testIncrementalCountIncludesOpenEventOnceLongEnough() {
        var merger = EventMerger()
        let run = windows(from: 0, count: 3)

        merger.add(run[0])
        merger.add(run[1])
        XCTAssertEqual(merger.eventCount, 0, "2.25 s isn't an event yet")

        merger.add(run[2])
        XCTAssertEqual(merger.eventCount, 1)
        XCTAssertEqual(merger.openEvent?.start, 0)
        XCTAssertTrue(merger.events.isEmpty, "Still open until a gap or finish()")

        XCTAssertEqual(merger.finish().count, 1)
        XCTAssertNil(merger.openEvent)
    }

    func testAddReportsWhetherWindowCounted() {
        var merger = EventMerger(threshold: 0.6)
        XCTAssertTrue(merger.add(DetectionWindow(start: 0, duration: 1.5, confidence: 0.8)))
        XCTAssertFalse(merger.add(DetectionWindow(start: 0.75, duration: 1.5, confidence: 0.3)))
    }

    func testSensitivityThresholds() {
        XCTAssertEqual(Sensitivity.low.threshold, 0.7)
        XCTAssertEqual(Sensitivity.normal.threshold, 0.6)
        XCTAssertEqual(Sensitivity.high.threshold, 0.5)
    }
}
