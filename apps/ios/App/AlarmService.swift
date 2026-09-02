import AppIntents
import AlarmKit
import ActivityKit
import Foundation
import OSLog
import SwiftUI

struct FeedingAlarmMetadata: AlarmMetadata {
    let eventID: String
}

actor AlarmService {
    private let policy = AlarmReconciliationPolicy()
    private let logger = Logger(
        subsystem: "com.btn0s.enzo.prototype",
        category: "feed-alarm"
    )
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    func reconcile(
        eventID: String?,
        dueAt: Date?,
        settings: FeedAlarmSettings
    ) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        do {
            try await reconcileFeed(
                eventID: eventID,
                dueAt: dueAt,
                settings: settings
            )
        } catch AlarmManager.AlarmError.maximumLimitReached {
            throw FeedingAlarmError.maximumLimitReached
        }
    }

    private func reconcileFeed(
        eventID: String?,
        dueAt: Date?,
        settings: FeedAlarmSettings
    ) async throws {
        let manager = AlarmManager.shared
        let feedTrigger = dueAt.map {
            AlarmTriggerCalculator.triggerDate(
                dueAt: $0,
                leadMinutes: settings.leadMinutes
            )
        }
        let storedAlarmID = AlarmRuntimeStore.alarmID
        let storedEventID = AlarmRuntimeStore.eventID
        let storedScheduledDate = AlarmRuntimeStore.scheduledDate
        let storedSourceDueAt = AlarmRuntimeStore.sourceDueAt
        let storedConfiguration = AlarmRuntimeStore.configurationSignature
        let storedIsReminder = AlarmRuntimeStore.isReminder
        let hasStoredAlarmForEvent = storedAlarmID != nil && storedEventID == eventID
        let mayNeedAlarm = settings.enabled
            && eventID != nil
            && (feedTrigger.map { settings.allowsAlarm(at: $0) } == true || hasStoredAlarmForEvent)

        // AlarmManager.alarms throws before authorization. Request permission
        // only when the current state may need an alarm.
        if mayNeedAlarm {
            try await ensureAuthorized(manager)
        } else if manager.authorizationState != .authorized {
            clearStoredAlarm()
            return
        }

        let currentAlarms = try manager.alarms
        let storedAlarm = currentAlarms.first { $0.id == storedAlarmID }
        let dueTimeChanged = storedEventID == eventID
            && storedSourceDueAt != nil
            && storedSourceDueAt != dueAt
        if dueTimeChanged {
            // Stopping the prior alarm only acknowledges its prior due time.
            // A server time correction for the same feed must schedule again.
            AlarmAcknowledgementStore.clear()
        }
        if storedAlarmID != nil,
           storedEventID == eventID,
           storedAlarm == nil,
           let eventID {
            if !dueTimeChanged {
                // The persisted alarm was consumed or dismissed. Never
                // recreate it without a new feed or corrected server time.
                AlarmAcknowledgementStore.acknowledge(
                    eventID: eventID,
                    dueAt: storedSourceDueAt ?? dueAt
                )
            }
            clearStoredAlarm()
        }

        let continuesReminder = policy.shouldContinueReminder(
            desiredEventID: eventID,
            desiredDueAt: dueAt,
            storedEventID: storedEventID,
            storedDueAt: storedSourceDueAt,
            isReminder: storedIsReminder,
            hasStoredAlarm: storedAlarm != nil
        )
        let targetDate = continuesReminder
            ? storedAlarm?.fixedDate ?? storedScheduledDate
            : feedTrigger
        let shouldSchedule = targetDate.map { settings.allowsAlarm(at: $0) } ?? false
        if continuesReminder,
           settings.enabled,
           settings.activeHoursEnabled,
           !shouldSchedule,
           let eventID {
            AlarmAcknowledgementStore.acknowledge(
                eventID: eventID,
                dueAt: storedSourceDueAt ?? dueAt
            )
        }

        let descriptors = currentAlarms.map { alarm in
            AlarmDescriptor(id: alarm.id, date: alarm.fixedDate)
        }
        let plan = policy.plan(
            desiredEventID: eventID,
            desiredDate: targetDate,
            desiredDueAt: dueAt,
            storedAlarmID: storedAlarmID,
            storedDesiredDate: storedScheduledDate,
            acknowledgedEventID: AlarmAcknowledgementStore.eventID,
            acknowledgedDueAt: AlarmAcknowledgementStore.dueAt,
            isEnabled: shouldSchedule,
            configurationMatches: storedConfiguration == settings.configurationSignature,
            alarms: descriptors
        )

        for alarmID in plan.cancelIDs {
            try manager.cancel(id: alarmID)
            logger.info("Cancelled obsolete feed alarm \(alarmID, privacy: .public)")
        }

        if let keepID = plan.keepID {
            if let targetDate, let eventID, let dueAt {
                AlarmRuntimeStore.save(
                    alarmID: keepID,
                    eventID: eventID,
                    scheduledDate: targetDate,
                    sourceDueAt: dueAt,
                    configurationSignature: settings.configurationSignature,
                    isReminder: continuesReminder
                )
            }
            logger.info("Kept feed alarm \(keepID, privacy: .public)")
            return
        }

        guard let request = plan.schedule, let dueAt else {
            clearStoredAlarm()
            return
        }

        let alarmID = UUID()
        let configuration = configuration(
            eventID: request.eventID,
            alarmID: alarmID,
            date: request.date,
            title: "Feed Enzo",
            settings: settings
        )
        try await scheduleFeedAlarm(
            id: alarmID,
            configuration: configuration,
            manager: manager
        )
        AlarmRuntimeStore.save(
            alarmID: alarmID,
            eventID: request.eventID,
            scheduledDate: request.date,
            sourceDueAt: dueAt,
            configurationSignature: settings.configurationSignature,
            isReminder: continuesReminder
        )
        logger.info("Scheduled feed alarm \(alarmID, privacy: .public) for \(request.date, privacy: .public)")
    }

    func resetAcknowledgement() {
        AlarmAcknowledgementStore.clear()
    }

    func scheduleSnooze(
        eventID: String,
        date: Date,
        settings: FeedAlarmSettings
    ) async throws {
        await acquireOperation()
        defer { releaseOperation() }

        let sourceDueAt = AlarmRuntimeStore.sourceDueAt ?? date

        let manager = AlarmManager.shared
        try await ensureAuthorized(manager)
        let alarmID = UUID()
        let configuration = configuration(
            eventID: eventID,
            alarmID: alarmID,
            date: date,
            title: "Feed Enzo",
            settings: settings
        )
        try await scheduleFeedAlarm(
            id: alarmID,
            configuration: configuration,
            manager: manager
        )
        AlarmRuntimeStore.save(
            alarmID: alarmID,
            eventID: eventID,
            scheduledDate: date,
            sourceDueAt: sourceDueAt,
            configurationSignature: settings.configurationSignature,
            isReminder: true
        )
        logger.info("Scheduled feed reminder \(alarmID, privacy: .public) for \(date, privacy: .public)")
    }

    /// Schedules a disposable near-term alarm so permission and the selected
    /// sound can be verified independently from feed timing.
    func scheduleTest(after seconds: TimeInterval = 10) async throws -> Date {
        await acquireOperation()
        defer { releaseOperation() }

        let manager = AlarmManager.shared
        try await ensureAuthorized(manager)
        let date = Date().addingTimeInterval(seconds)
        let alarmID = UUID()
        var settings = AlarmSettingsStore.shared.settings
        settings.enabled = true
        settings.cadence = .once
        settings.activeHoursEnabled = false
        let configuration = configuration(
            eventID: "alarm-test",
            alarmID: alarmID,
            date: date,
            title: "Enzo test alarm",
            settings: settings,
            acknowledgesEvent: false
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
        alarmID: UUID,
        date: Date,
        title: LocalizedStringResource,
        settings: FeedAlarmSettings,
        acknowledgesEvent: Bool = true
    ) -> AlarmManager.AlarmConfiguration<FeedingAlarmMetadata> {
        let supportsReminder = acknowledgesEvent && settings.cadence.repeatMinutes != nil
        let secondaryButton = supportsReminder
            ? AlarmButton(
                text: "Remind me",
                textColor: .white,
                systemImageName: "clock.arrow.circlepath"
            )
            : nil
        let presentation = AlarmPresentation(
            alert: .init(
                title: title,
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: supportsReminder ? .custom : nil
            )
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: FeedingAlarmMetadata(eventID: eventID),
            tintColor: Color(red: 0.55, green: 0.31, blue: 0.22)
        )
        let stopIntent: (any LiveActivityIntent)? = acknowledgesEvent
            ? AcknowledgeFeedAlarmIntent(eventID: eventID)
            : nil
        let secondaryIntent: (any LiveActivityIntent)? = supportsReminder
            ? SnoozeFeedAlarmIntent(eventID: eventID, alarmID: alarmID)
            : nil
        let sound: AlertConfiguration.AlertSound
        if let fileName = settings.sound.fileName {
            sound = .named(fileName)
        } else {
            sound = .default
        }
        return AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent,
            sound: sound
        )
    }

    private func clearStoredAlarm() {
        AlarmRuntimeStore.clear()
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
