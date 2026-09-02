import ActivityKit
import Foundation
import OSLog

struct WaitingFeedActivity {
    let eventID: String
    let nextFeedAt: Date
}

private actor LiveActivityPushRegistrar {
    static let shared = LiveActivityPushRegistrar()

    private let logger = Logger(
        subsystem: "com.btn0s.enzo.prototype",
        category: "live-activity-push"
    )
    private struct Observation {
        let eventID: String
        let task: Task<Void, Never>
    }

    private var observations: [String: Observation] = [:]

    func observe(
        _ activity: Activity<FeedActivityAttributes>,
        eventID: String
    ) {
        let activityID = activity.id
        if observations[activityID]?.eventID == eventID { return }
        observations.removeValue(forKey: activityID)?.task.cancel()
        let initialToken = activity.pushToken

        let task = Task { [logger] in
            if let initialToken {
                await register(
                    initialToken,
                    activityID: activityID,
                    eventID: eventID,
                    logger: logger
                )
            }
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                await register(
                    token,
                    activityID: activityID,
                    eventID: eventID,
                    logger: logger
                )
            }
        }
        observations[activityID] = Observation(eventID: eventID, task: task)
    }

    func stopObserving(activityID: String) async {
        observations.removeValue(forKey: activityID)?.task.cancel()
        do {
            try await APIClient().unregisterLiveActivity(activityID: activityID)
        } catch {
            logger.error(
                "Unable to unregister Live Activity \(activityID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func register(
        _ token: Data,
        activityID: String,
        eventID: String,
        logger: Logger
    ) async {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        do {
            try await APIClient().registerLiveActivity(
                token: tokenString,
                activityID: activityID,
                eventID: eventID,
                environment: .current
            )
            logger.info("Registered Live Activity \(activityID, privacy: .public) for remote updates")
        } catch {
            logger.error(
                "Unable to register Live Activity \(activityID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

struct ActivityService {
    private let logger = Logger(
        subsystem: "com.btn0s.enzo.prototype",
        category: "live-activity"
    )
    private let policy = LiveActivityReconciliationPolicy()
    private let registrar = LiveActivityPushRegistrar.shared

    func reconcile(
        _ desired: WaitingFeedActivity?,
        now: Date = Date(),
        canRequestActivity: Bool = true
    ) async {
        let currentActivities = Activity<FeedActivityAttributes>.activities
        let descriptors = currentActivities.map {
            LiveActivityDescriptor(
                id: $0.id,
                state: descriptorState(for: $0.activityState),
                createdAt: $0.attributes.createdAt,
                eventID: $0.attributes.eventID,
                supportsRemoteUpdates: $0.attributes.supportsRemoteUpdates == true
            )
        }
        let plan = policy.plan(
            desiredEventID: desired?.eventID,
            activities: descriptors,
            now: now,
            canRequestActivity: canRequestActivity
        )

        guard let desired else {
            for activity in currentActivities where plan.endIDs.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
                await registrar.stopObserving(activityID: activity.id)
                logger.info("Ended obsolete Live Activity \(activity.id, privacy: .public)")
            }
            return
        }
        let content = ActivityContent(
            state: FeedActivityAttributes.ContentState(nextFeedAt: desired.nextFeedAt),
            // The countdown remains valid after it reaches zero. Marking it
            // stale at the due time only weakens an activity we still need.
            staleDate: nil
        )

        if let updateID = plan.updateID,
           let activity = currentActivities.first(where: { $0.id == updateID }) {
            for obsolete in currentActivities where plan.endIDs.contains(obsolete.id) {
                await obsolete.end(nil, dismissalPolicy: .immediate)
                await registrar.stopObserving(activityID: obsolete.id)
                logger.info("Ended obsolete Live Activity \(obsolete.id, privacy: .public)")
            }
            await registrar.observe(activity, eventID: desired.eventID)
            await activity.update(content)
            logger.info("Updated Live Activity \(activity.id, privacy: .public)")
            return
        }

        guard plan.shouldRequest, canRequestActivity else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities are disabled for Enzo")
            return
        }

        do {
            let activity = try Activity.request(
                attributes: FeedActivityAttributes(
                    eventID: desired.eventID,
                    createdAt: now,
                    supportsRemoteUpdates: true
                ),
                content: content,
                pushType: .token
            )
            await registrar.observe(activity, eventID: desired.eventID)
            for obsolete in currentActivities where plan.endIDs.contains(obsolete.id) {
                await obsolete.end(nil, dismissalPolicy: .immediate)
                await registrar.stopObserving(activityID: obsolete.id)
                logger.info("Ended obsolete Live Activity \(obsolete.id, privacy: .public)")
            }
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
