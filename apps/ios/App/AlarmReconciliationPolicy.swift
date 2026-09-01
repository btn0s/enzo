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
        storedAlarmID: UUID?,
        storedDesiredDate: Date? = nil,
        alarms: [AlarmDescriptor]
    ) -> AlarmReconciliationPlan {
        guard let desiredEventID, let desiredDate else {
            return AlarmReconciliationPlan(
                keepID: nil,
                cancelIDs: alarms.map(\.id),
                schedule: nil
            )
        }

        let storedAlarm = alarms.first { $0.id == storedAlarmID }
        let reusable = storedDesiredDate == desiredDate
            ? storedAlarm
            : alarms.first { $0.date == desiredDate }

        return AlarmReconciliationPlan(
            keepID: reusable?.id,
            cancelIDs: alarms.filter { $0.id != reusable?.id }.map(\.id),
            schedule: reusable == nil
                ? AlarmScheduleRequest(eventID: desiredEventID, date: desiredDate)
                : nil
        )
    }
}
