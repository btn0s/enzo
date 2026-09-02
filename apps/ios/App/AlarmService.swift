import AlarmKit
import Foundation
import OSLog
import SwiftUI

struct FeedingAlarmMetadata: AlarmMetadata {
    let eventID: String
}

actor AlarmService {
    private let alarmIDKey = "enzo.prototype.feed-alarm-id"
    private let desiredDateKey = "enzo.prototype.feed-alarm-desired-date"
    private let policy = AlarmReconciliationPolicy()
    private let logger = Logger(
        subsystem: "com.btn0s.enzo.prototype",
        category: "feed-alarm"
    )
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    func reconcile(eventID: String?, dueAt: Date?, leadMinutes: Int) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        do {
            try await reconcileFeed(eventID: eventID, dueAt: dueAt, leadMinutes: leadMinutes)
        } catch AlarmManager.AlarmError.maximumLimitReached {
            throw FeedingAlarmError.maximumLimitReached
        }
    }

    private func reconcileFeed(eventID: String?, dueAt: Date?, leadMinutes: Int) async throws {
        let manager = AlarmManager.shared
        let triggerDate = dueAt.map {
            AlarmTriggerCalculator.triggerDate(
                dueAt: $0,
                leadMinutes: leadMinutes
            )
        }

        // AlarmManager.alarms throws before authorization. Request permission
        // first whenever there is an alarm to schedule; otherwise first-run
        // reconciliation never reaches requestAuthorization().
        if eventID != nil, triggerDate != nil {
            try await ensureAuthorized(manager)
        } else if manager.authorizationState != .authorized {
            clearStoredAlarm()
            return
        }

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
            desiredDate: triggerDate,
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
            if let triggerDate {
                UserDefaults.standard.set(triggerDate, forKey: desiredDateKey)
            }
            logger.info("Kept feed alarm \(keepID, privacy: .public)")
            return
        }

        guard let request = plan.schedule else {
            clearStoredAlarm()
            return
        }

        let alarmID = UUID()
        let configuration = configuration(
            eventID: request.eventID,
            date: request.date,
            title: "Feed Enzo"
        )
        try await scheduleFeedAlarm(
            id: alarmID,
            configuration: configuration,
            manager: manager
        )
        UserDefaults.standard.set(alarmID.uuidString, forKey: alarmIDKey)
        UserDefaults.standard.set(request.date, forKey: desiredDateKey)
        logger.info("Scheduled feed alarm \(alarmID, privacy: .public) for \(request.date, privacy: .public)")
    }

    /// Schedules a disposable near-term alarm so permission and sound can be
    /// verified independently from feed timing.
    func scheduleTest(after seconds: TimeInterval = 10) async throws -> Date {
        await acquireOperation()
        defer { releaseOperation() }

        let manager = AlarmManager.shared
        try await ensureAuthorized(manager)
        let date = Date().addingTimeInterval(seconds)
        let alarmID = UUID()
        let configuration = configuration(
            eventID: "alarm-test",
            date: date,
            title: "Enzo test alarm"
        )
        do {
            _ = try await manager.schedule(id: alarmID, configuration: configuration)
        } catch AlarmManager.AlarmError.maximumLimitReached {
            throw FeedingAlarmError.maximumLimitReached
        }
        logger.info("Scheduled test alarm \(alarmID, privacy: .public) for \(date, privacy: .public)")
        return date
    }

    private func scheduleFeedAlarm(
        id: UUID,
        configuration: AlarmManager.AlarmConfiguration<FeedingAlarmMetadata>,
        manager: AlarmManager
    ) async throws {
        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
        } catch AlarmManager.AlarmError.maximumLimitReached {
            let appAlarms = try manager.alarms
            for alarm in appAlarms {
                try manager.cancel(id: alarm.id)
                logger.info("Cancelled alarm \(alarm.id, privacy: .public) while recovering alarm capacity")
            }
            clearStoredAlarm()

            // AlarmKit cancellation is asynchronous internally; give it a
            // moment to release capacity before the single retry.
            try await Task.sleep(for: .milliseconds(250))
            do {
                _ = try await manager.schedule(id: id, configuration: configuration)
            } catch AlarmManager.AlarmError.maximumLimitReached {
                throw FeedingAlarmError.maximumLimitReached
            }
        }
    }

    private func acquireOperation() async {
        if !operationInProgress {
            operationInProgress = true
            return
        }

        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        guard !operationWaiters.isEmpty else {
            operationInProgress = false
            return
        }
        operationWaiters.removeFirst().resume()
    }

    private func ensureAuthorized(_ manager: AlarmManager) async throws {
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
    }

    private func configuration(
        eventID: String,
        date: Date,
        title: LocalizedStringResource
    ) -> AlarmManager.AlarmConfiguration<FeedingAlarmMetadata> {
        let presentation = AlarmPresentation(alert: .init(title: title))
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: FeedingAlarmMetadata(eventID: eventID),
            tintColor: Color(red: 0.55, green: 0.31, blue: 0.22)
        )
        return AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes
        )
    }

    private func clearStoredAlarm() {
        UserDefaults.standard.removeObject(forKey: alarmIDKey)
        UserDefaults.standard.removeObject(forKey: desiredDateKey)
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
    case maximumLimitReached

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Alarm permission is off. Enable Alarms for Enzo in Settings."
        case .maximumLimitReached:
            "The system alarm limit is full. Try scheduling the feed alarm again in a moment."
        }
    }
}
