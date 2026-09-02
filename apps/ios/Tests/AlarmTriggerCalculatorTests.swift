import Foundation
import XCTest
@testable import Enzo

final class AlarmTriggerCalculatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testZeroLeadUsesDueTime() {
        let dueAt = now.addingTimeInterval(3_600)
        let trigger = AlarmTriggerCalculator.triggerDate(
            dueAt: dueAt,
            leadMinutes: 0,
            now: now
        )
        XCTAssertEqual(trigger, dueAt)
    }

    func testPositiveLeadSubtractsMinutes() {
        let dueAt = now.addingTimeInterval(3_600)
        let trigger = AlarmTriggerCalculator.triggerDate(
            dueAt: dueAt,
            leadMinutes: 15,
            now: now
        )
        XCTAssertEqual(trigger, dueAt.addingTimeInterval(-15 * 60))
    }

    func testPastTriggerUsesImmediateFloor() {
        let dueAt = now.addingTimeInterval(5 * 60)
        let trigger = AlarmTriggerCalculator.triggerDate(
            dueAt: dueAt,
            leadMinutes: 15,
            now: now
        )
        XCTAssertEqual(
            trigger,
            now.addingTimeInterval(AlarmTriggerCalculator.immediateFloorOffset)
        )
    }

    func testClampsLeadToMaximum() {
        let dueAt = now.addingTimeInterval(200 * 60)
        let trigger = AlarmTriggerCalculator.triggerDate(
            dueAt: dueAt,
            leadMinutes: 999,
            now: now
        )
        XCTAssertEqual(trigger, dueAt.addingTimeInterval(-180 * 60))
    }
}
