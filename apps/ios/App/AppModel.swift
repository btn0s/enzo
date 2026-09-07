import Foundation
import Observation
import WidgetKit

struct ServerStateRequestGate {
    private var latestRequest = 0

    mutating func beginRequest() -> Int {
        latestRequest += 1
        return latestRequest
    }

    func accepts(_ request: Int) -> Bool {
        request == latestRequest
    }
}

@MainActor
@Observable
final class AppModel {
    private enum SettingsKey {
        static let volumeUnit = "enzo.settings.volumeUnit"
    }

    var state: ServerState?
    var editor: EditorRoute?
    var status = "Ready"
    var isBusy = false
    var alarmWarning: String?
    var alarmTestMessage: String?
    /// True after the first `load()` finishes, success or failure.
    var hasCompletedInitialLoad = false
    var alarmsEnabled: Bool
    var alarmLeadMinutes: Int
    var alarmCadence: AlarmCadence
    var alarmActiveHoursEnabled: Bool
    var alarmActiveHoursStartMinutes: Int
    var alarmActiveHoursEndMinutes: Int
    var alarmSound: AlarmSound
    var volumeUnit: VolumeUnit {
        didSet {
            defaults.set(volumeUnit.rawValue, forKey: SettingsKey.volumeUnit)
            publishWidgetSnapshot()
        }
    }

    /// Server-known birth time; falls back to the documented default until the
    /// first sync so day-of-life still renders offline.
    var birthDate: Date {
        state?.profile.birthAt ?? Self.defaultBirthDate
    }

    var profile: EnzoProfile { EnzoProfile(birthDate: birthDate) }

    var currentWeightKg: Double? {
        state?.currentWeightKg
    }

    var defaultFeedIntervalMinutes: Int {
        state?.profile.feedIntervalMinutes ?? state?.intervalMinutes ?? 120
    }

    /// Goals in effect at a point in time: latest checkup on top of guidance.
    func goals(now: Date = Date()) -> DailyGoals {
        DailyGoals.resolve(
            checkup: state?.activeCheckup(at: now),
            weightKg: state?.currentWeightKg(at: now),
            day: profile.dayOfLife(on: now, calendar: state?.careCalendar ?? .current),
            hoursOfAge: profile.hoursOfAge(at: now),
            defaultIntervalMinutes: defaultFeedIntervalMinutes
        )
    }

    /// Feed-alarm trigger for the current next feed, if any.
    func feedAlarmTrigger(at now: Date = Date()) -> Date? {
        guard let state,
              let waiting = waitingActivity(for: state),
              !isAlarmAcknowledged(waiting) else { return nil }
        guard let timing = AlarmTriggerCalculator.scheduleTiming(
            dueAt: waiting.nextFeedAt,
            leadMinutes: alarmLeadMinutes,
            now: now
        ) else { return nil }
        return feedAlarmSettings.allowsAlarm(at: timing.scheduledDate)
            ? timing.scheduledDate
            : nil
    }

    var currentFeedAlarmAcknowledged: Bool {
        guard let state, let waiting = waitingActivity(for: state) else { return false }
        return isAlarmAcknowledged(waiting)
    }

    private static let defaultBirthDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 8, day: 28, hour: 21)
    )!

    private let defaults: UserDefaults
    private let api = APIClient()
    private let activities = ActivityService()
    private let alarms = AlarmService()
    private let alarmSettingsStore: AlarmSettingsStore
    private var stateRequestGate = ServerStateRequestGate()

    init(
        defaults: UserDefaults = .standard,
        alarmSettingsStore: AlarmSettingsStore = .shared
    ) {
        self.defaults = defaults
        self.alarmSettingsStore = alarmSettingsStore
        volumeUnit = defaults.string(forKey: SettingsKey.volumeUnit).flatMap(VolumeUnit.init) ?? .ounces
        let alarmSettings = alarmSettingsStore.settings
        alarmsEnabled = alarmSettings.enabled
        alarmLeadMinutes = AlarmTriggerCalculator.leadRange.clamp(alarmSettings.leadMinutes)
        alarmCadence = alarmSettings.cadence
        alarmActiveHoursEnabled = alarmSettings.activeHoursEnabled
        alarmActiveHoursStartMinutes = (0...1439).clamp(alarmSettings.activeHoursStartMinutes)
        alarmActiveHoursEndMinutes = (0...1439).clamp(alarmSettings.activeHoursEndMinutes)
        alarmSound = alarmSettings.sound
    }

    func saveBirthDate(_ birthAt: Date) async {
        await perform { request in
            let response = try await api.updateBirthDate(birthAt)
            guard stateRequestGate.accepts(request) else { return }
            state = response.state
            let warning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus("Birthday saved", response: response, surfaceWarning: warning)
        }
    }

    func saveFeedIntervalMinutes(_ minutes: Int) async {
        guard FeedIntervalFormatting.options.contains(minutes),
              minutes != defaultFeedIntervalMinutes else { return }
        await perform { request in
            let response = try await api.updateFeedIntervalMinutes(minutes)
            guard stateRequestGate.accepts(request) else { return }
            state = response.state
            let warning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus(
                "Feed interval updated",
                response: response,
                surfaceWarning: warning
            )
        }
    }

    func saveCheckup(_ checkup: Checkup, isNew: Bool) async {
        await perform { request in
            let response = try await (isNew ? api.createCheckup(checkup) : api.updateCheckup(checkup))
            guard stateRequestGate.accepts(request) else { return }
            state = response.state
            let warning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus(isNew ? "Checkup added" : "Checkup updated", response: response, surfaceWarning: warning)
        }
    }

    func deleteCheckup(id: String) async {
        await perform { request in
            let response = try await api.deleteCheckup(id: id)
            guard stateRequestGate.accepts(request) else { return }
            state = response.state
            let warning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus("Checkup deleted", response: response, surfaceWarning: warning)
        }
    }

    func load() async {
        defer { hasCompletedInitialLoad = true }
        do {
            try await syncState(successStatus: "Synced")
        } catch {
            status = "Offline: \(error.localizedDescription)"
        }
    }

    func registerPushToken(
        _ token: String,
        environment: PushEnvironment
    ) async {
        do {
            try await api.registerPushDevice(token: token, environment: environment)
        } catch {
            status = "Server updates unavailable: \(error.localizedDescription)"
        }
    }

    func recordPushRegistrationFailure(_ error: Error) {
        status = "Server updates unavailable: \(error.localizedDescription)"
    }

    func refreshFromRemoteNotification() async -> Bool {
        do {
            try await syncState(
                successStatus: "Updated from server",
                canRequestActivity: false
            )
            return true
        } catch {
            status = "Server update failed: \(error.localizedDescription)"
            return false
        }
    }

    private func syncState(
        successStatus: String,
        canRequestActivity: Bool = true
    ) async throws {
        guard !isBusy else { return }
        let request = stateRequestGate.beginRequest()
        let syncedState = try await api.state()
        guard stateRequestGate.accepts(request) else { return }
        state = syncedState
        if let warning = await reconcileSystemSurfaces(
            for: syncedState,
            canRequestActivity: canRequestActivity
        ) {
            status = "\(successStatus); \(warning)"
        } else {
            status = successStatus
        }
    }

    func setAlarmsEnabled(_ enabled: Bool) async {
        guard enabled != alarmsEnabled else { return }
        alarmsEnabled = enabled
        if enabled {
            await alarms.resetAcknowledgement()
        }
        await alarmSettingDidChange(enabled ? "Alarms turned on" : "Alarms turned off")
    }

    func setAlarmLeadMinutes(_ minutes: Int) async {
        let clamped = AlarmTriggerCalculator.leadRange.clamp(minutes)
        guard clamped != alarmLeadMinutes else { return }
        alarmLeadMinutes = clamped
        await alarmSettingDidChange("Alarm lead updated")
    }

    func setAlarmCadence(_ cadence: AlarmCadence) async {
        guard cadence != alarmCadence else { return }
        alarmCadence = cadence
        await alarmSettingDidChange("Alarm cadence updated")
    }

    func setAlarmActiveHoursEnabled(_ enabled: Bool) async {
        guard enabled != alarmActiveHoursEnabled else { return }
        alarmActiveHoursEnabled = enabled
        await alarmSettingDidChange(enabled ? "Active hours turned on" : "Active hours turned off")
    }

    func setAlarmActiveHours(startMinutes: Int? = nil, endMinutes: Int? = nil) async {
        let start = (0...1439).clamp(startMinutes ?? alarmActiveHoursStartMinutes)
        let end = (0...1439).clamp(endMinutes ?? alarmActiveHoursEndMinutes)
        guard start != alarmActiveHoursStartMinutes || end != alarmActiveHoursEndMinutes else { return }
        alarmActiveHoursStartMinutes = start
        alarmActiveHoursEndMinutes = end
        await alarmSettingDidChange("Active hours updated")
    }

    func setAlarmSound(_ sound: AlarmSound) async {
        guard sound != alarmSound else { return }
        alarmSound = sound
        await alarmSettingDidChange("Alarm sound updated")
    }

    func presentNewFeed(now: Date = Date()) {
        var draft = FeedDraft()
        if let nextFeedAt = state?.nextFeedAt,
           now >= nextFeedAt,
           now.timeIntervalSince(nextFeedAt) <= 30 * 60 {
            draft.occurredAt = nextFeedAt
        } else {
            draft.occurredAt = now
        }
        editor = .feed(draft)
    }

    func presentNewDiaper(now: Date = Date()) {
        var draft = DiaperDraft()
        draft.occurredAt = now
        editor = .diaper(draft)
    }

    func presentEditor(for event: ServerEvent) {
        editor = EditorRoute(event: event)
    }

    func saveFeed(_ draft: FeedDraft) async {
        await perform { request in
            let response = try await (draft.eventID == nil ? api.createFeed(draft) : api.updateFeed(draft))
            guard stateRequestGate.accepts(request) else { return }
            state = response.state
            let surfaceWarning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus(
                draft.eventID == nil ? "Feed logged" : "Feed updated",
                response: response,
                surfaceWarning: surfaceWarning
            )
        }
    }

    func saveDiaper(_ draft: DiaperDraft) async {
        await perform { request in
            let response = try await (draft.eventID == nil ? api.createDiaper(draft) : api.updateDiaper(draft))
            guard stateRequestGate.accepts(request) else { return }
            state = response.state
            let surfaceWarning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus(
                draft.eventID == nil ? "Diaper logged" : "Diaper updated",
                response: response,
                surfaceWarning: surfaceWarning
            )
        }
    }

    func deleteEvent(id: String) async {
        await perform { request in
            let response = try await api.deleteEvent(id: id)
            guard stateRequestGate.accepts(request) else { return }
            state = response.state
            let surfaceWarning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus(
                "Event deleted",
                response: response,
                surfaceWarning: surfaceWarning
            )
        }
    }

    func testAlarm() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let date = try await alarms.scheduleTest()
            alarmWarning = nil
            alarmTestMessage = "Test alarm scheduled for \(date.formatted(date: .omitted, time: .standard))"
            status = "Test alarm scheduled"
        } catch {
            alarmWarning = error.localizedDescription
            alarmTestMessage = nil
            status = "Alarm unavailable: \(error.localizedDescription)"
        }
    }

    private var feedAlarmSettings: FeedAlarmSettings {
        FeedAlarmSettings(
            enabled: alarmsEnabled,
            leadMinutes: alarmLeadMinutes,
            cadence: alarmCadence,
            activeHoursEnabled: alarmActiveHoursEnabled,
            activeHoursStartMinutes: alarmActiveHoursStartMinutes,
            activeHoursEndMinutes: alarmActiveHoursEndMinutes,
            sound: alarmSound
        )
    }

    private func persistAlarmSettings() {
        alarmSettingsStore.save(feedAlarmSettings)
    }

    private func alarmSettingDidChange(_ success: String) async {
        persistAlarmSettings()
        guard let state else {
            status = success
            return
        }
        if let warning = await reconcileAlarms(for: state) {
            status = "\(success); \(warning)"
        } else {
            status = success
        }
    }

    private func waitingActivity(for state: ServerState) -> WaitingFeedActivity? {
        guard let nextFeedAt = state.nextFeedAt else { return nil }
        let sourceEvent = state.events
            .filter { $0.feed?.resetsTimer == true }
            .max(by: { $0.occurredAt < $1.occurredAt })
        guard let sourceEvent else { return nil }

        return WaitingFeedActivity(
            eventID: sourceEvent.id,
            nextFeedAt: nextFeedAt
        )
    }

    private func isAlarmAcknowledged(_ waiting: WaitingFeedActivity) -> Bool {
        waiting.eventID == AlarmAcknowledgementStore.eventID
            && waiting.nextFeedAt == AlarmAcknowledgementStore.dueAt
    }

    private func reconcileSystemSurfaces(
        for state: ServerState,
        canRequestActivity: Bool = true
    ) async -> String? {
        publishWidgetSnapshot()
        let waiting = waitingActivity(for: state)
        await activities.reconcile(
            waiting,
            canRequestActivity: canRequestActivity
        )
        return await reconcileAlarms(for: state)
    }

    private func reconcileAlarms(for state: ServerState) async -> String? {
        let waiting = waitingActivity(for: state)
        do {
            try await alarms.reconcile(
                eventID: waiting?.eventID,
                dueAt: waiting?.nextFeedAt,
                settings: feedAlarmSettings
            )
            alarmWarning = nil
            return nil
        } catch {
            alarmWarning = error.localizedDescription
            return "alarm unavailable: \(error.localizedDescription)"
        }
    }

    private func publishWidgetSnapshot() {
        guard let state else { return }
        WidgetSnapshotStore.save(WidgetSnapshot(
            nextFeedAt: state.nextFeedAt,
            milkMl: state.today.milkMl,
            feeds: state.today.feeds,
            pees: state.today.pees,
            poops: state.today.poops,
            dayOfLife: profile.dayOfLife(),
            volumeUnit: volumeUnit,
            updatedAt: Date()
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func mutationStatus(
        _ success: String,
        response: MutationResponse,
        surfaceWarning: String?
    ) -> String {
        guard let surfaceWarning else { return success }
        return "\(success); \(surfaceWarning)"
    }

    private func perform(_ work: (Int) async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        let request = stateRequestGate.beginRequest()
        defer { isBusy = false }
        do { try await work(request) }
        catch { status = "Couldn't save: \(error.localizedDescription)" }
    }
}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
