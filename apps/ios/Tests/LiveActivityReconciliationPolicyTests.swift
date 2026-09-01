import XCTest
@testable import Enzo

final class LiveActivityReconciliationPolicyTests: XCTestCase {
    private let policy = LiveActivityReconciliationPolicy()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRequestsAnActivityWhenTrackerHasScheduleButActivityIsMissing() {
        let plan = policy.plan(hasDesiredActivity: true, activities: [], now: now)

        XCTAssertTrue(plan.shouldRequest)
        XCTAssertNil(plan.updateID)
        XCTAssertEqual(plan.endIDs, [])
    }

    func testUpdatesFreshActiveActivity() {
        let activity = descriptor(id: "fresh", state: .active, age: 3 * 60 * 60)

        let plan = policy.plan(
            hasDesiredActivity: true,
            activities: [activity],
            now: now
        )

        XCTAssertFalse(plan.shouldRequest)
        XCTAssertEqual(plan.updateID, "fresh")
        XCTAssertEqual(plan.endIDs, [])
    }

    func testRotatesActivityBeforeEightHourSystemLimit() {
        let activity = descriptor(id: "old", state: .active, age: 6 * 60 * 60)

        let plan = policy.plan(
            hasDesiredActivity: true,
            activities: [activity],
            now: now
        )

        XCTAssertTrue(plan.shouldRequest)
        XCTAssertNil(plan.updateID)
        XCTAssertEqual(plan.endIDs, ["old"])
    }

    func testReplacesEndedOrDismissedActivities() {
        let ended = descriptor(id: "ended", state: .ended, age: 60)
        let dismissed = descriptor(id: "dismissed", state: .dismissed, age: 60)

        let plan = policy.plan(
            hasDesiredActivity: true,
            activities: [ended, dismissed],
            now: now
        )

        XCTAssertTrue(plan.shouldRequest)
        XCTAssertEqual(Set(plan.endIDs), ["ended", "dismissed"])
    }

    func testEndsAllActivitiesWhenTrackerHasNoNextFeed() {
        let activity = descriptor(id: "active", state: .active, age: 60)

        let plan = policy.plan(
            hasDesiredActivity: false,
            activities: [activity],
            now: now
        )

        XCTAssertFalse(plan.shouldRequest)
        XCTAssertNil(plan.updateID)
        XCTAssertEqual(plan.endIDs, ["active"])
    }

    private func descriptor(
        id: String,
        state: LiveActivityDescriptor.State,
        age: TimeInterval
    ) -> LiveActivityDescriptor {
        LiveActivityDescriptor(
            id: id,
            state: state,
            createdAt: now.addingTimeInterval(-age)
        )
    }
}
