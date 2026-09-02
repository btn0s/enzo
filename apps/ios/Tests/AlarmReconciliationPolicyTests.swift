import Foundation
import XCTest
@testable import Enzo

final class AlarmReconciliationPolicyTests: XCTestCase {
    private let policy = AlarmReconciliationPolicy()
    private let dueAt = Date(timeIntervalSince1970: 1_800_010_800)

    func testSchedulesExistingFeedWhenAppLoadsWithoutAnAlarm() {
        let plan = policy.plan(
            desiredEventID: "feed-midnight",
            desiredDate: dueAt,
            storedAlarmID: nil,
            alarms: []
        )

        XCTAssertEqual(
            plan,
            AlarmReconciliationPlan(
                keepID: nil,
                cancelIDs: [],
                schedule: AlarmScheduleRequest(
                    eventID: "feed-midnight",
                    date: dueAt
                )
            )
        )
    }

    func testDoesNotRecreateAcknowledgedOneTimeAlarm() {
        let stoppedAlarmID = UUID()
        let plan = policy.plan(
            desiredEventID: "feed-midnight",
            desiredDate: dueAt,
            desiredDueAt: dueAt,
            storedAlarmID: stoppedAlarmID,
            acknowledgedEventID: "feed-midnight",
            acknowledgedDueAt: dueAt,
            isEnabled: true,
            alarms: []
        )

        XCTAssertNil(plan.keepID)
        XCTAssertEqual(plan.cancelIDs, [])
        XCTAssertNil(plan.schedule)
    }

    func testReplacesAcknowledgedAlarmWhenServerDueTimeChanges() {
        let oldAlarmID = UUID()
        let oldDueAt = dueAt.addingTimeInterval(-60 * 60)
        let plan = policy.plan(
            desiredEventID: "feed-midnight",
            desiredDate: dueAt,
            desiredDueAt: dueAt,
            storedAlarmID: oldAlarmID,
            acknowledgedEventID: "feed-midnight",
            acknowledgedDueAt: oldDueAt,
            alarms: [AlarmDescriptor(id: oldAlarmID, date: oldDueAt)]
        )

        XCTAssertNil(plan.keepID)
        XCTAssertEqual(plan.cancelIDs, [oldAlarmID])
        XCTAssertEqual(
            plan.schedule,
            AlarmScheduleRequest(eventID: "feed-midnight", date: dueAt)
        )
    }

    func testUpdatedDueTimeStopsReusingSnoozedReminder() {
        XCTAssertFalse(policy.shouldContinueReminder(
            desiredEventID: "feed-midnight",
            desiredDueAt: dueAt,
            storedEventID: "feed-midnight",
            storedDueAt: dueAt.addingTimeInterval(-60 * 60),
            isReminder: true,
            hasStoredAlarm: true
        ))
    }

    func testUnchangedDueTimeKeepsSnoozedReminder() {
        XCTAssertTrue(policy.shouldContinueReminder(
            desiredEventID: "feed-midnight",
            desiredDueAt: dueAt,
            storedEventID: "feed-midnight",
            storedDueAt: dueAt,
            isReminder: true,
            hasStoredAlarm: true
        ))
    }

    func testDisabledAlarmCancelsExistingAlarmWithoutReplacement() {
        let alarmID = UUID()
        let plan = policy.plan(
            desiredEventID: "feed-midnight",
            desiredDate: dueAt,
            storedAlarmID: alarmID,
            acknowledgedEventID: nil,
            isEnabled: false,
            alarms: [AlarmDescriptor(id: alarmID, date: dueAt)]
        )

        XCTAssertNil(plan.keepID)
        XCTAssertEqual(plan.cancelIDs, [alarmID])
        XCTAssertNil(plan.schedule)
    }

    func testKeepsMatchingScheduledAlarm() {
        let alarmID = UUID()
        let plan = policy.plan(
            desiredEventID: "feed-midnight",
            desiredDate: dueAt,
            storedAlarmID: alarmID,
            alarms: [AlarmDescriptor(id: alarmID, date: dueAt)]
        )

        XCTAssertEqual(plan.keepID, alarmID)
        XCTAssertEqual(plan.cancelIDs, [])
        XCTAssertNil(plan.schedule)
    }

    func testReplacesAlarmWhenNextFeedChanges() {
        let alarmID = UUID()
        let oldDate = dueAt.addingTimeInterval(-60 * 60)
        let plan = policy.plan(
            desiredEventID: "feed-midnight",
            desiredDate: dueAt,
            storedAlarmID: alarmID,
            alarms: [AlarmDescriptor(id: alarmID, date: oldDate)]
        )

        XCTAssertEqual(plan.cancelIDs, [alarmID])
        XCTAssertEqual(plan.schedule?.date, dueAt)
    }

    func testKeepsImmediateAlarmCreatedForAnOverdueFeed() {
        let alarmID = UUID()
        let immediateDate = dueAt.addingTimeInterval(10 * 60)
        let plan = policy.plan(
            desiredEventID: "feed-midnight",
            desiredDate: dueAt,
            storedAlarmID: alarmID,
            storedDesiredDate: dueAt,
            alarms: [AlarmDescriptor(id: alarmID, date: immediateDate)]
        )

        XCTAssertEqual(plan.keepID, alarmID)
        XCTAssertNil(plan.schedule)
    }

    func testConfigurationChangeReplacesMatchingAlarm() {
        let alarmID = UUID()
        let plan = policy.plan(
            desiredEventID: "feed-midnight",
            desiredDate: dueAt,
            storedAlarmID: alarmID,
            storedDesiredDate: dueAt,
            configurationMatches: false,
            alarms: [AlarmDescriptor(id: alarmID, date: dueAt)]
        )

        XCTAssertNil(plan.keepID)
        XCTAssertEqual(plan.cancelIDs, [alarmID])
        XCTAssertEqual(plan.schedule?.date, dueAt)
    }

    func testCancelsAlarmWhenThereIsNoNextFeed() {
        let alarmID = UUID()
        let plan = policy.plan(
            desiredEventID: nil,
            desiredDate: nil,
            storedAlarmID: alarmID,
            alarms: [AlarmDescriptor(id: alarmID, date: dueAt)]
        )

        XCTAssertNil(plan.keepID)
        XCTAssertEqual(plan.cancelIDs, [alarmID])
        XCTAssertNil(plan.schedule)
    }
}
