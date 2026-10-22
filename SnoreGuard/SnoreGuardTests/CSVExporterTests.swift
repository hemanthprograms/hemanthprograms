import SwiftData
import XCTest
@testable import SnoreGuard

final class CSVExporterTests: XCTestCase {
    func testEscaping() {
        XCTAssertEqual(CSVExporter.escape("Nasal strip"), "Nasal strip")
        XCTAssertEqual(CSVExporter.escape("Pillow, extra"), "\"Pillow, extra\"")
        XCTAssertEqual(CSVExporter.escape("The \"good\" pillow"), "\"The \"\"good\"\" pillow\"")
    }

    func testExportContainsEveryNightAndEvent() throws {
        let context = try TestStore.makeContext()
        RemedyCatalog.seedBuiltIns(in: context)
        let remedy = try XCTUnwrap(RemedyCatalog.remedy(withKey: "side", in: context))
        let night = Night(startDate: Date(timeIntervalSince1970: 1_700_000_000), threshold: 0.6, source: .microphone)
        context.insert(night)
        night.remedy = remedy
        night.addEvent(DetectedEvent(start: 60, duration: 30, peakConfidence: 0.81), in: context)
        night.addEvent(DetectedEvent(start: 600, duration: 45, peakConfidence: 0.92), in: context)
        night.recordedDuration = 7 * 3600
        night.recomputeTotals()

        let nightsLines = CSVExporter.nightsCSV([night]).split(separator: "\n")
        XCTAssertEqual(nightsLines.count, 2)
        XCTAssertTrue(nightsLines[0].hasPrefix("night_id,start,end,remedy"))
        XCTAssertTrue(nightsLines[1].contains(",Sleep on side,7.00,1.25,0.18,2,0.60,microphone,yes,no"))

        let eventLines = CSVExporter.eventsCSV([night]).split(separator: "\n")
        XCTAssertEqual(eventLines.count, 3)
        XCTAssertTrue(eventLines[1].hasSuffix(",30.0,0.810"))
    }
}
