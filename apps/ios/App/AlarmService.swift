import AlarmKit
import Foundation
import OSLog
import SwiftUI

struct FeedingAlarmMetadata: AlarmMetadata {
    let eventID: String
}

struct AlarmService {
    private let alarmIDKey = "enzo.prototype.feed-alarm-id"
    private let desiredDateKey = "enzo.prototype.feed-alarm-desired-date"
    private let policy = AlarmReconciliationPolicy()
    private let logger = Logger(
        subsystem: "com.btn0s.enzo.prototype",
        category: "feed-alarm"
    )

    func reconcile(eventID: String?, at date: Date?) async throws {
        let manager = AlarmManager.shared
        let currentAlarms = try manager.alarms
        let storedAlarmID = UserDefaults.standard
            .string(forKey: alarmIDKey)
            .flatMap(UUID.init(uuidString:))
        let storedDesiredDate = UserDefaults.standard.object(forKey: desiredDateKey) as? Date
        let descriptors = currentAlarms.map { alarm in
            AlarmDescriptor(id: alarm.id, date: alarm.fixedDate)
        }
        let plan = policy.plan(
            desiredEventID: eventID,
            desiredDate: date,
            storedAlarmID: storedAlarmID,
            storedDesiredDate: storedDesiredDate,
            alarms: descriptors
        )

        for alarmID in plan.cancelIDs {
            try manager.cancel(id: alarmID)
            logger.info("Cancelled obsolete feed alarm \(alarmID, privacy: .public)")
        }

        if let keepID = plan.keepID {
            UserDefaults.standard.set(keepID.uuidString, forKey: alarmIDKey)
            if let date {
                UserDefaults.standard.set(date, forKey: desiredDateKey)
            }
            logger.info("Kept feed alarm \(keepID, privacy: .public)")
            return
        }

        guard let request = plan.schedule else {
            UserDefaults.standard.removeObject(forKey: alarmIDKey)
            UserDefaults.standard.removeObject(forKey: desiredDateKey)
            return
        }

        let authorization: AlarmManager.AuthorizationState
        switch manager.authorizationState {
        case .authorized:
            authorization = .authorized
        case .notDetermined:
            authorization = try await manager.requestAuthorization()
        case .denied:
            authorization = .denied
        @unknown default:
            authorization = .denied
        }
        guard authorization == .authorized else {
            throw FeedingAlarmError.authorizationDenied
        }

        let alarmID = UUID()
        let presentation = AlarmPresentation(
            alert: .init(title: "Feed Enzo"),
            countdown: .init(title: "Next feeding")
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: FeedingAlarmMetadata(eventID: request.eventID),
            tintColor: Color(red: 0.55, green: 0.31, blue: 0.22)
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(max(request.date, Date().addingTimeInterval(2))),
            attributes: attributes
        )
        _ = try await manager.schedule(id: alarmID, configuration: configuration)
        UserDefaults.standard.set(alarmID.uuidString, forKey: alarmIDKey)
        UserDefaults.standard.set(request.date, forKey: desiredDateKey)
        logger.info("Scheduled feed alarm \(alarmID, privacy: .public) for \(request.date, privacy: .public)")
    }
}

private extension Alarm {
    var fixedDate: Date? {
        guard case .fixed(let date) = schedule else { return nil }
        return date
    }
}

enum FeedingAlarmError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Alarm permission is off"
        }
    }
}
