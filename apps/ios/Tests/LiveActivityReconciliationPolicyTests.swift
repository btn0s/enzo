import XCTest
@testable import Enzo

final class LiveActivityReconciliationPolicyTests: XCTestCase {
    private let policy = LiveActivityReconciliationPolicy()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRequestsAnActivityWhenTrackerHasScheduleButActivityIsMissing() {
        let plan = policy.plan(desiredEventID: "feed-current", activities: [], now: now)

        XCTAssertTrue(plan.shouldRequest)
        XCTAssertNil(plan.updateID)
        XCTAssertEqual(plan.endIDs, [])
    }

    func testUpdatesFreshActiveActivityForSameFeed() {
        let activity = descriptor(id: "fresh", state: .active, age: 3 * 60 * 60)

        let plan = policy.plan(
            desiredEventID: "feed-current",
            activities: [activity],
            now: now
        )

        XCTAssertFalse(plan.shouldRequest)
        XCTAssertEqual(plan.updateID, "fresh")
        XCTAssertEqual(plan.endIDs, [])
    }

    func testReplacesLegacyActivityWithoutRemotePushToken() {
        let legacy = descriptor(
            id: "legacy",
            state: .active,
            age: 30 * 60,
            supportsRemoteUpdates: false
        )

        let plan = policy.plan(
            desiredEventID: "feed-current",
            activities: [legacy],
            now: now
        )

        XCTAssertTrue(plan.shouldRequest)
        XCTAssertNil(plan.updateID)
        XCTAssertEqual(plan.endIDs, ["legacy"])
    }

    func testReusesRemoteActivityWhenAnotherDeviceLogsFeed() {
        let previousFeed = descriptor(
            id: "previous",
            eventID: "feed-previous",
            state: .active,
            age: 30 * 60
        )

        let plan = policy.plan(
            desiredEventID: "feed-current",
            activities: [previousFeed],
            now: now
        )

        XCTAssertFalse(plan.shouldRequest)
        XCTAssertEqual(plan.updateID, "previous")
        XCTAssertEqual(plan.endIDs, [])
    }

    func testRotatesActivityBeforeEightHourSystemLimit() {
        let activity = descriptor(id: "old", state: .active, age: 6 * 60 * 60)

        let plan = policy.plan(
            desiredEventID: "feed-current",
            activities: [activity],
            now: now
        )

        XCTAssertTrue(plan.shouldRequest)
        XCTAssertNil(plan.updateID)
        XCTAssertEqual(plan.endIDs, ["old"])
    }

    func testKeepsOldActivityWhenBackgroundCannotRequestReplacement() {
        let old = descriptor(id: "old", state: .active, age: 7 * 60 * 60)

        let plan = policy.plan(
            desiredEventID: "feed-current",
            activities: [old],
            now: now,
            canRequestActivity: false
        )

        XCTAssertFalse(plan.shouldRequest)
        XCTAssertEqual(plan.updateID, "old")
        XCTAssertEqual(plan.endIDs, [])
    }

    func testKeepsLegacyActivityWhenBackgroundCannotRequestReplacement() {
        let legacy = descriptor(
            id: "legacy",
            state: .active,
            age: 30 * 60,
            supportsRemoteUpdates: false
        )

        let plan = policy.plan(
            desiredEventID: "feed-current",
            activities: [legacy],
            now: now,
            canRequestActivity: false
        )

        XCTAssertFalse(plan.shouldRequest)
        XCTAssertEqual(plan.updateID, "legacy")
        XCTAssertEqual(plan.endIDs, [])
    }

    func testReplacesEndedOrDismissedActivities() {
        let ended = descriptor(id: "ended", state: .ended, age: 60)
        let dismissed = descriptor(id: "dismissed", state: .dismissed, age: 60)

        let plan = policy.plan(
            desiredEventID: "feed-current",
            activities: [ended, dismissed],
            now: now
        )

        XCTAssertTrue(plan.shouldRequest)
        XCTAssertEqual(Set(plan.endIDs), ["ended", "dismissed"])
    }

    func testEndsAllActivitiesWhenTrackerHasNoNextFeed() {
        let activity = descriptor(id: "active", state: .active, age: 60)
        let plan = policy.plan(desiredEventID: nil, activities: [activity], now: now)

        XCTAssertFalse(plan.shouldRequest)
        XCTAssertNil(plan.updateID)
        XCTAssertEqual(plan.endIDs, ["active"])
    }

    private func descriptor(
        id: String,
        eventID: String = "feed-current",
        state: LiveActivityDescriptor.State,
        age: TimeInterval,
        supportsRemoteUpdates: Bool = true
    ) -> LiveActivityDescriptor {
        LiveActivityDescriptor(
            id: id,
            state: state,
            createdAt: now.addingTimeInterval(-age),
            eventID: eventID,
            supportsRemoteUpdates: supportsRemoteUpdates
        )
    }
}
