import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class AppModel {
    private enum SettingsKey {
        static let volumeUnit = "enzo.settings.volumeUnit"
        static let alarmLeadMinutes = "enzo.settings.alarmLeadMinutes"
    }

    var state: ServerState?
    var editor: EditorRoute?
    var status = "Ready"
    var isBusy = false
    var alarmWarning: String?
    var alarmTestMessage: String?
    /// True after the first `load()` finishes, success or failure.
    var hasCompletedInitialLoad = false
    var alarmLeadMinutes: Int
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

    /// Today's goals: active checkup on top of guidance.
    func goals(now: Date = Date()) -> DailyGoals {
        DailyGoals.resolve(
            checkup: state?.activeCheckup,
            weightKg: state?.currentWeightKg,
            day: profile.dayOfLife(on: now),
            hoursOfAge: profile.hoursOfAge(at: now),
            defaultIntervalMinutes: state?.intervalMinutes ?? 180
        )
    }

    /// Feed-alarm trigger for the current next feed, if any.
    func feedAlarmTrigger(at now: Date = Date()) -> Date? {
        guard let dueAt = state?.nextFeedAt else { return nil }
        return AlarmTriggerCalculator.triggerDate(
            dueAt: dueAt,
            leadMinutes: alarmLeadMinutes,
            now: now
        )
    }

    private static let defaultBirthDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 8, day: 28, hour: 21)
    )!

    private let defaults: UserDefaults
    private let api = APIClient()
    private let activities = ActivityService()
    private let alarms = AlarmService()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        volumeUnit = defaults.string(forKey: SettingsKey.volumeUnit).flatMap(VolumeUnit.init) ?? .ounces
        let storedLead = defaults.object(forKey: SettingsKey.alarmLeadMinutes) as? Int ?? 0
        alarmLeadMinutes = AlarmTriggerCalculator.leadRange.clamp(storedLead)
    }

    func saveBirthDate(_ birthAt: Date) async {
        await perform {
            let response = try await api.updateProfile(birthAt: birthAt)
            state = response.state
            let warning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus("Birthday saved", response: response, surfaceWarning: warning)
        }
    }

    func saveCheckup(_ checkup: Checkup, isNew: Bool) async {
        await perform {
            let response = try await (isNew ? api.createCheckup(checkup) : api.updateCheckup(checkup))
            state = response.state
            let warning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus(isNew ? "Checkup added" : "Checkup updated", response: response, surfaceWarning: warning)
        }
    }

    func deleteCheckup(id: String) async {
        await perform {
            let response = try await api.deleteCheckup(id: id)
            state = response.state
            let warning = await reconcileSystemSurfaces(for: response.state)
            status = mutationStatus("Checkup deleted", response: response, surfaceWarning: warning)
        }
    }

    func load() async {
        defer { hasCompletedInitialLoad = true }
        do {
            let syncedState = try await api.state()
            state = syncedState
            if let warning = await reconcileSystemSurfaces(for: syncedState) {
                status = "Synced; \(warning)"
            } else {
                status = "Synced"
            }
        } catch {
            status = "Offline: \(error.localizedDescription)"
        }
    }

    func setAlarmLeadMinutes(_ minutes: Int) async {
        let clamped = AlarmTriggerCalculator.leadRange.clamp(minutes)
        guard clamped != alarmLeadMinutes else { return }
        alarmLeadMinutes = clamped
        defaults.set(clamped, forKey: SettingsKey.alarmLeadMinutes)
        guard let state else { return }
        if let warning = await reconcileAlarms(for: state) {
            status = "Alarm lead updated; \(warning)"
        } else {
            status = "Alarm lead updated"
        }
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
        await perform {
            let response = try await (draft.eventID == nil ? api.createFeed(draft) : api.updateFeed(draft))
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
        await perform {
            let response = try await (draft.eventID == nil ? api.createDiaper(draft) : api.updateDiaper(draft))
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
        await perform {
            let response = try await api.deleteEvent(id: id)
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

    private func reconcileSystemSurfaces(for state: ServerState) async -> String? {
        publishWidgetSnapshot()
        let waiting = waitingActivity(for: state)
        await activities.reconcile(waiting)
        return await reconcileAlarms(for: state)
    }

    private func reconcileAlarms(for state: ServerState) async -> String? {
        let waiting = waitingActivity(for: state)
        do {
            try await alarms.reconcile(
                eventID: waiting?.eventID,
                dueAt: waiting?.nextFeedAt,
                leadMinutes: alarmLeadMinutes
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

    private func perform(_ work: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await work() }
        catch { status = "Couldn't save: \(error.localizedDescription)" }
    }
}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int {
        min(max(value, lowerBound), upperBound)
    }
}
