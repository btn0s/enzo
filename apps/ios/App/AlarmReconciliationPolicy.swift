import Foundation

struct AlarmDescriptor: Equatable {
    let id: UUID
    let date: Date?
}

struct AlarmScheduleRequest: Equatable {
    let eventID: String
    let date: Date
}

struct AlarmReconciliationPlan: Equatable {
    let keepID: UUID?
    let cancelIDs: [UUID]
    let schedule: AlarmScheduleRequest?
}

struct AlarmReconciliationPolicy {
    func plan(
        desiredEventID: String?,
        desiredDate: Date?,
        scheduledDate: Date? = nil,
        desiredDueAt: Date? = nil,
        storedAlarmID: UUID?,
        storedDesiredDate: Date? = nil,
        acknowledgedEventID: String? = nil,
        acknowledgedDueAt: Date? = nil,
        isEnabled: Bool = true,
        configurationMatches: Bool = true,
        alarms: [AlarmDescriptor]
    ) -> AlarmReconciliationPlan {
        let acknowledgementMatches = desiredEventID == acknowledgedEventID
            && desiredDueAt != nil
            && desiredDueAt == acknowledgedDueAt
        guard isEnabled,
              let desiredEventID,
              let desiredDate,
              !acknowledgementMatches else {
            return AlarmReconciliationPlan(
                keepID: nil,
                cancelIDs: alarms.map(\.id),
                schedule: nil
            )
        }
        let scheduleDate = scheduledDate ?? desiredDate

        let storedAlarm = alarms.first { $0.id == storedAlarmID }
        let reusable: AlarmDescriptor?
        if configurationMatches {
            reusable = storedDesiredDate == desiredDate
                ? storedAlarm
                : alarms.first { $0.date == desiredDate }
        } else {
            reusable = nil
        }
        return AlarmReconciliationPlan(
            keepID: reusable?.id,
            cancelIDs: alarms.filter { $0.id != reusable?.id }.map(\.id),
            schedule: reusable == nil
                ? AlarmScheduleRequest(eventID: desiredEventID, date: scheduleDate)
                : nil
        )
    }

    func shouldContinueReminder(
        desiredEventID: String?,
        desiredDueAt: Date?,
        storedEventID: String?,
        storedDueAt: Date?,
        isReminder: Bool,
        hasStoredAlarm: Bool
    ) -> Bool {
        isReminder
            && hasStoredAlarm
            && storedEventID == desiredEventID
            && (storedDueAt == nil || storedDueAt == desiredDueAt)
    }
}
