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

    func testOverdueFeedDoesNotProduceAnAlarmSchedule() {
        let timing = AlarmTriggerCalculator.scheduleTiming(
            dueAt: now.addingTimeInterval(-60),
            leadMinutes: 0,
            now: now
        )

        XCTAssertNil(timing)
    }

    func testUpcomingImmediateScheduleKeepsAStableDesiredDate() throws {
        let dueAt = now.addingTimeInterval(5 * 60)
        let first = try XCTUnwrap(AlarmTriggerCalculator.scheduleTiming(
            dueAt: dueAt,
            leadMinutes: 15,
            now: now
        ))
        let second = try XCTUnwrap(AlarmTriggerCalculator.scheduleTiming(
            dueAt: dueAt,
            leadMinutes: 15,
            now: now.addingTimeInterval(30)
        ))

        XCTAssertEqual(first.desiredDate, dueAt.addingTimeInterval(-15 * 60))
        XCTAssertEqual(second.desiredDate, first.desiredDate)
        XCTAssertNotEqual(second.scheduledDate, first.scheduledDate)
    }
}
