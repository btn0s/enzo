import AlarmKit
import Foundation

enum AlarmRuntimeStore {
    private enum Key {
        static let alarmID = "enzo.feed-alarm.id"
        static let eventID = "enzo.feed-alarm.event-id"
        static let scheduledDate = "enzo.feed-alarm.scheduled-date"
        static let desiredDate = "enzo.feed-alarm.desired-date"
        static let sourceDueAt = "enzo.feed-alarm.source-due-at"
        static let configuration = "enzo.feed-alarm.configuration"
        static let isReminder = "enzo.feed-alarm.is-reminder"
    }

    private static let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup) ?? .standard

    static var alarmID: UUID? {
        defaults.string(forKey: Key.alarmID).flatMap(UUID.init(uuidString:))
    }

    static var eventID: String? {
        defaults.string(forKey: Key.eventID)
    }

    static var scheduledDate: Date? {
        defaults.object(forKey: Key.scheduledDate) as? Date
    }

    static var desiredDate: Date? {
        defaults.object(forKey: Key.desiredDate) as? Date
    }

    static var sourceDueAt: Date? {
        defaults.object(forKey: Key.sourceDueAt) as? Date
    }

    static var configurationSignature: String? {
        defaults.string(forKey: Key.configuration)
    }

    static var isReminder: Bool {
        defaults.bool(forKey: Key.isReminder)
    }

    static func save(
        alarmID: UUID,
        eventID: String,
        scheduledDate: Date,
        desiredDate: Date,
        sourceDueAt: Date,
        configurationSignature: String,
        isReminder: Bool
    ) {
        defaults.set(alarmID.uuidString, forKey: Key.alarmID)
        defaults.set(eventID, forKey: Key.eventID)
        defaults.set(scheduledDate, forKey: Key.scheduledDate)
        defaults.set(desiredDate, forKey: Key.desiredDate)
        defaults.set(sourceDueAt, forKey: Key.sourceDueAt)
        defaults.set(configurationSignature, forKey: Key.configuration)
        defaults.set(isReminder, forKey: Key.isReminder)
    }

    static func cancelIfStale(remoteDueAt: Date?) throws {
        guard let staleAlarmID = alarmID, sourceDueAt != remoteDueAt else { return }
        try AlarmManager.shared.cancel(id: staleAlarmID)
        guard alarmID == staleAlarmID, sourceDueAt != remoteDueAt else { return }
        clear()
    }

    static func clear() {
        defaults.removeObject(forKey: Key.alarmID)
        defaults.removeObject(forKey: Key.eventID)
        defaults.removeObject(forKey: Key.scheduledDate)
        defaults.removeObject(forKey: Key.desiredDate)
        defaults.removeObject(forKey: Key.sourceDueAt)
        defaults.removeObject(forKey: Key.configuration)
        defaults.removeObject(forKey: Key.isReminder)
    }
}
