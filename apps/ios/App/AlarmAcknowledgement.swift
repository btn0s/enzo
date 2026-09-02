import AlarmKit
import AppIntents
import Foundation

enum AlarmCadence: String, CaseIterable, Identifiable, Sendable {
    case once
    case fiveMinutes
    case tenMinutes
    case fifteenMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: "Once"
        case .fiveMinutes: "Every 5 minutes"
        case .tenMinutes: "Every 10 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        }
    }

    var repeatMinutes: Int? {
        switch self {
        case .once: nil
        case .fiveMinutes: 5
        case .tenMinutes: 10
        case .fifteenMinutes: 15
        }
    }
}

enum AlarmSound: String, CaseIterable, Identifiable, Sendable {
    case system
    case gentleChime
    case brightChime
    case bell
    case classicAlarm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System default"
        case .gentleChime: "Gentle chime"
        case .brightChime: "Bright chime"
        case .bell: "Bell"
        case .classicAlarm: "Classic alarm"
        }
    }

    var fileName: String? {
        switch self {
        case .system: nil
        case .gentleChime: "EnzoGentleChime.wav"
        case .brightChime: "EnzoBrightChime.wav"
        case .bell: "EnzoBell.wav"
        case .classicAlarm: "EnzoClassicAlarm.wav"
        }
    }
}

struct FeedAlarmSettings: Equatable, Sendable {
    var enabled: Bool
    var leadMinutes: Int
    var cadence: AlarmCadence
    var activeHoursEnabled: Bool
    var activeHoursStartMinutes: Int
    var activeHoursEndMinutes: Int
    var sound: AlarmSound

    func allowsAlarm(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        guard activeHoursEnabled else { return true }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = activeHoursStartMinutes
        let end = activeHoursEndMinutes
        if start == end { return true }
        if start < end { return start <= minutes && minutes < end }
        return minutes >= start || minutes < end
    }

    var configurationSignature: String {
        [
            String(enabled),
            String(leadMinutes),
            cadence.rawValue,
            String(activeHoursEnabled),
            String(activeHoursStartMinutes),
            String(activeHoursEndMinutes),
            sound.rawValue,
        ].joined(separator: ":")
    }
}

struct AlarmSettingsStore {
    static let shared = AlarmSettingsStore()

    private enum Key {
        static let enabled = "enzo.alarm.enabled"
        static let leadMinutes = "enzo.alarm.lead-minutes"
        static let cadence = "enzo.alarm.cadence"
        static let activeHoursEnabled = "enzo.alarm.active-hours-enabled"
        static let activeHoursStart = "enzo.alarm.active-hours-start"
        static let activeHoursEnd = "enzo.alarm.active-hours-end"
        static let sound = "enzo.alarm.sound"
    }

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup) ?? .standard
    ) {
        self.defaults = defaults
    }

    var settings: FeedAlarmSettings {
        FeedAlarmSettings(
            enabled: defaults.object(forKey: Key.enabled) as? Bool ?? true,
            leadMinutes: defaults.object(forKey: Key.leadMinutes) as? Int ?? 0,
            cadence: defaults.string(forKey: Key.cadence).flatMap(AlarmCadence.init(rawValue:)) ?? .once,
            activeHoursEnabled: defaults.object(forKey: Key.activeHoursEnabled) as? Bool ?? false,
            activeHoursStartMinutes: defaults.object(forKey: Key.activeHoursStart) as? Int ?? 7 * 60,
            activeHoursEndMinutes: defaults.object(forKey: Key.activeHoursEnd) as? Int ?? 22 * 60,
            sound: defaults.string(forKey: Key.sound).flatMap(AlarmSound.init(rawValue:)) ?? .system
        )
    }

    func save(_ settings: FeedAlarmSettings) {
        defaults.set(settings.enabled, forKey: Key.enabled)
        defaults.set(settings.leadMinutes, forKey: Key.leadMinutes)
        defaults.set(settings.cadence.rawValue, forKey: Key.cadence)
        defaults.set(settings.activeHoursEnabled, forKey: Key.activeHoursEnabled)
        defaults.set(settings.activeHoursStartMinutes, forKey: Key.activeHoursStart)
        defaults.set(settings.activeHoursEndMinutes, forKey: Key.activeHoursEnd)
        defaults.set(settings.sound.rawValue, forKey: Key.sound)
    }
}

enum AlarmRuntimeStore {
    private enum Key {
        static let alarmID = "enzo.feed-alarm.id"
        static let eventID = "enzo.feed-alarm.event-id"
        static let scheduledDate = "enzo.feed-alarm.scheduled-date"
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
        sourceDueAt: Date,
        configurationSignature: String,
        isReminder: Bool
    ) {
        defaults.set(alarmID.uuidString, forKey: Key.alarmID)
        defaults.set(eventID, forKey: Key.eventID)
        defaults.set(scheduledDate, forKey: Key.scheduledDate)
        defaults.set(sourceDueAt, forKey: Key.sourceDueAt)
        defaults.set(configurationSignature, forKey: Key.configuration)
        defaults.set(isReminder, forKey: Key.isReminder)
    }

    static func clear() {
        defaults.removeObject(forKey: Key.alarmID)
        defaults.removeObject(forKey: Key.eventID)
        defaults.removeObject(forKey: Key.scheduledDate)
        defaults.removeObject(forKey: Key.sourceDueAt)
        defaults.removeObject(forKey: Key.configuration)
        defaults.removeObject(forKey: Key.isReminder)
    }
}

enum AlarmAcknowledgementStore {
    private enum Key {
        static let eventID = "enzo.feed-alarm.acknowledged-event-id"
        static let dueAt = "enzo.feed-alarm.acknowledged-due-at"
    }

    private static let defaults = UserDefaults(suiteName: WidgetSnapshotStore.appGroup) ?? .standard

    static var eventID: String? {
        defaults.string(forKey: Key.eventID)
    }

    static var dueAt: Date? {
        defaults.object(forKey: Key.dueAt) as? Date
    }

    static func acknowledge(eventID: String, dueAt: Date?) {
        defaults.set(eventID, forKey: Key.eventID)
        defaults.set(dueAt, forKey: Key.dueAt)
    }

    static func clear() {
        defaults.removeObject(forKey: Key.eventID)
        defaults.removeObject(forKey: Key.dueAt)
    }
}

struct AcknowledgeFeedAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Acknowledge feed alarm"

    @Parameter(title: "Feed event")
    var eventID: String

    init() {}

    init(eventID: String) {
        self.eventID = eventID
    }

    func perform() async throws -> some IntentResult {
        AlarmAcknowledgementStore.acknowledge(
            eventID: eventID,
            dueAt: AlarmRuntimeStore.sourceDueAt
        )
        AlarmRuntimeStore.clear()
        return .result()
    }
}

struct SnoozeFeedAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Remind me again"

    @Parameter(title: "Feed event")
    var eventID: String

    @Parameter(title: "Alarm")
    var alarmID: String

    init() {}

    init(eventID: String, alarmID: UUID) {
        self.eventID = eventID
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let sourceDueAt = AlarmRuntimeStore.sourceDueAt
        if let currentID = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: currentID)
        }
        let settings = AlarmSettingsStore.shared.settings
        guard let repeatMinutes = settings.cadence.repeatMinutes else {
            AlarmAcknowledgementStore.acknowledge(eventID: eventID, dueAt: sourceDueAt)
            AlarmRuntimeStore.clear()
            return .result()
        }
        let nextDate = Date().addingTimeInterval(TimeInterval(repeatMinutes * 60))
        guard settings.allowsAlarm(at: nextDate) else {
            AlarmAcknowledgementStore.acknowledge(eventID: eventID, dueAt: sourceDueAt)
            AlarmRuntimeStore.clear()
            return .result()
        }
        do {
            try await AlarmService().scheduleSnooze(
                eventID: eventID,
                date: nextDate,
                settings: settings
            )
        } catch {
            AlarmAcknowledgementStore.acknowledge(eventID: eventID, dueAt: sourceDueAt)
            AlarmRuntimeStore.clear()
            throw error
        }
        return .result()
    }
}
