import ActivityKit
import Foundation
import OSLog

struct WaitingFeedActivity {
    let eventID: String
    let nextFeedAt: Date
    let milkType: String
}

struct ActivityService {
    private let logger = Logger(
        subsystem: "com.btn0s.enzo.prototype",
        category: "live-activity"
    )
    private let policy = LiveActivityReconciliationPolicy()

    func reconcile(_ desired: WaitingFeedActivity?, now: Date = Date()) async {
        let currentActivities = Activity<FeedActivityAttributes>.activities
        let descriptors = currentActivities.map {
            LiveActivityDescriptor(
                id: $0.id,
                state: descriptorState(for: $0.activityState),
                createdAt: $0.attributes.createdAt
            )
        }
        let plan = policy.plan(
            hasDesiredActivity: desired != nil,
            activities: descriptors,
            now: now
        )

        for activity in currentActivities where plan.endIDs.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
            logger.info("Ended obsolete Live Activity \(activity.id, privacy: .public)")
        }

        guard let desired else { return }
        let content = ActivityContent(
            state: FeedActivityAttributes.ContentState(
                phase: .waiting,
                startedAt: nil,
                nextFeedAt: desired.nextFeedAt,
                milkType: desired.milkType
            ),
            // The countdown remains valid after it reaches zero. Marking it
            // stale at the due time only weakens an activity we still need.
            staleDate: nil
        )

        if let updateID = plan.updateID,
           let activity = currentActivities.first(where: { $0.id == updateID }) {
            await activity.update(content)
            logger.info("Updated Live Activity \(activity.id, privacy: .public)")
            return
        }

        guard plan.shouldRequest else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities are disabled for Enzo")
            return
        }

        do {
            let activity = try Activity.request(
                attributes: FeedActivityAttributes(
                    eventID: desired.eventID,
                    createdAt: now
                ),
                content: content,
                pushType: nil
            )
            logger.info("Started Live Activity \(activity.id, privacy: .public)")
        } catch {
            logger.error("Unable to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func descriptorState(
        for state: ActivityState
    ) -> LiveActivityDescriptor.State {
        switch state {
        case .active: .active
        case .stale: .stale
        case .pending: .pending
        case .ended: .ended
        case .dismissed: .dismissed
        @unknown default: .ended
        }
    }
}
