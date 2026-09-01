import Foundation

struct LiveActivityDescriptor: Equatable {
    enum State: Equatable {
        case active
        case stale
        case pending
        case ended
        case dismissed
    }

    let id: String
    let state: State
    let createdAt: Date
}

struct LiveActivityReconciliationPlan: Equatable {
    let updateID: String?
    let endIDs: [String]
    let shouldRequest: Bool
}

struct LiveActivityReconciliationPolicy {
    // Feed saves normally happen every three hours. Rotating at six hours gives
    // the replacement a safe margin before ActivityKit's eight-hour hard cap.
    static let maximumReusableAge: TimeInterval = 6 * 60 * 60

    func plan(
        hasDesiredActivity: Bool,
        activities: [LiveActivityDescriptor],
        now: Date
    ) -> LiveActivityReconciliationPlan {
        guard hasDesiredActivity else {
            return LiveActivityReconciliationPlan(
                updateID: nil,
                endIDs: activities.map(\.id),
                shouldRequest: false
            )
        }

        let reusable = activities
            .filter { descriptor in
                let canUpdate = descriptor.state == .active || descriptor.state == .stale
                let age = now.timeIntervalSince(descriptor.createdAt)
                return canUpdate && age >= 0 && age < Self.maximumReusableAge
            }
            .max { $0.createdAt < $1.createdAt }

        return LiveActivityReconciliationPlan(
            updateID: reusable?.id,
            endIDs: activities.filter { $0.id != reusable?.id }.map(\.id),
            shouldRequest: reusable == nil
        )
    }
}
