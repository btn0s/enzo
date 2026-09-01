import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private enum ProfileKey {
        static let birthDate = "enzo.profile.birthDate"
        static let currentWeightKg = "enzo.profile.currentWeightKg"
        static let weightUpdatedAt = "enzo.profile.weightUpdatedAt"
    }

    private static let defaultBirthDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 8, day: 28)
    )!

    var state: ServerState?
    var editor: EditorRoute?
    var status = "Ready"
    var typedCommand = ProcessInfo.processInfo.environment["ENZO_SMOKE_COMMAND"] ?? ""
    var lastTranscript = ""
    var isBusy = false
    var birthDate: Date {
        didSet { defaults.set(birthDate, forKey: ProfileKey.birthDate) }
    }
    var currentWeightKg: Double? {
        didSet {
            if let currentWeightKg {
                defaults.set(currentWeightKg, forKey: ProfileKey.currentWeightKg)
            } else {
                defaults.removeObject(forKey: ProfileKey.currentWeightKg)
            }
        }
    }
    var weightUpdatedAt: Date? {
        didSet {
            if let weightUpdatedAt {
                defaults.set(weightUpdatedAt, forKey: ProfileKey.weightUpdatedAt)
            } else {
                defaults.removeObject(forKey: ProfileKey.weightUpdatedAt)
            }
        }
    }
    private var didRunSmokeCommand = false

    let voice = VoiceInput()
    private let defaults: UserDefaults
    private let api = APIClient()
    private let activities = ActivityService()
    private let alarms = AlarmService()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        birthDate = defaults.object(forKey: ProfileKey.birthDate) as? Date
            ?? Self.defaultBirthDate
        currentWeightKg = (defaults.object(forKey: ProfileKey.currentWeightKg) as? NSNumber)?.doubleValue
        weightUpdatedAt = defaults.object(forKey: ProfileKey.weightUpdatedAt) as? Date
    }

    func updateCurrentWeight(kilograms: Double) {
        guard kilograms > 0 else { return }
        currentWeightKg = kilograms
        weightUpdatedAt = Date()
    }

    func load() async {
        do {
            let syncedState = try await api.state()
            state = syncedState
            if let warning = await reconcileSystemSurfaces(for: syncedState) {
                status = "Synced; \(warning)"
            } else {
                status = "Synced"
            }
            if !didRunSmokeCommand,
               let smokeCommand = ProcessInfo.processInfo.environment["ENZO_AUTORUN_COMMAND"],
               !smokeCommand.isEmpty {
                didRunSmokeCommand = true
                await process(smokeCommand)
            }
        } catch {
            status = "Offline: \(error.localizedDescription)"
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
        switch event.content {
        case .feed(let feed):
            var draft = FeedDraft()
            draft.eventID = event.id
            draft.occurredAt = event.occurredAt
            draft.milkType = feed.milkType
            draft.amountMl = feed.amountMl
            draft.notes = event.notes
            draft.resetsTimer = feed.resetsTimer
            editor = .feed(draft)
        case .diaper(let diaper):
            var draft = DiaperDraft()
            draft.eventID = event.id
            draft.occurredAt = event.occurredAt
            draft.pee = diaper.pee
            draft.poop = diaper.poop
            draft.notes = event.notes
            editor = .diaper(draft)
        }
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

    func beginVoice() async {
        typedCommand = ""
        await voice.start()
        status = voice.isListening
            ? "Listening"
            : voice.errorMessage ?? "Couldn't start dictation"
    }

    func finishVoice() async {
        let transcript = await voice.stop()
        typedCommand = transcript
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "No speech heard"
            return
        }
        await processTypedCommand()
    }

    func stopVoiceForReview() async {
        let transcript = await voice.stop()
        typedCommand = transcript
        status = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No speech heard"
            : "Ready to send"
    }

    func cancelVoice() async {
        await voice.cancel()
        typedCommand = ""
        status = "Ready"
    }

    func processTypedCommand() async {
        let command = typedCommand
        typedCommand = ""
        await process(command)
    }

    func handle(url: URL) {
        guard url.scheme == "enzo", url.host == "feed" else { return }
        presentNewFeed()
    }

    private func process(_ transcript: String) async {
        lastTranscript = transcript
        switch CommandParser.parse(transcript, feedDefaultTime: smartFeedDate()) {
        case .feed(let draft):
            if draft.amountMl == nil {
                editor = .feed(draft)
                status = "Add the amount"
            } else {
                await saveFeed(draft)
            }
        case .diaper(let draft):
            await saveDiaper(draft)
        case .unrecognized:
            status = "I couldn't turn that into an event"
        }
    }

    private func smartFeedDate(now: Date = Date()) -> Date {
        guard let nextFeedAt = state?.nextFeedAt,
              now >= nextFeedAt,
              now.timeIntervalSince(nextFeedAt) <= 30 * 60 else { return now }
        return nextFeedAt
    }

    private func waitingActivity(for state: ServerState) -> WaitingFeedActivity? {
        guard let nextFeedAt = state.nextFeedAt else { return nil }
        let sourceEvent = state.events
            .filter { $0.feed?.resetsTimer == true }
            .max(by: { $0.occurredAt < $1.occurredAt })
        guard let sourceEvent,
              let feed = sourceEvent.feed else { return nil }

        return WaitingFeedActivity(
            eventID: sourceEvent.id,
            nextFeedAt: nextFeedAt,
            milkType: feed.milkType.rawValue
        )
    }

    private func reconcileSystemSurfaces(for state: ServerState) async -> String? {
        let waiting = waitingActivity(for: state)
        await activities.reconcile(waiting)
        do {
            try await alarms.reconcile(
                eventID: waiting?.eventID,
                at: waiting?.nextFeedAt
            )
            return nil
        } catch {
            return "alarm unavailable: \(error.localizedDescription)"
        }
    }

    private func mutationStatus(
        _ success: String,
        response: MutationResponse,
        surfaceWarning: String?
    ) -> String {
        var warnings: [String] = []
        if let legacySync = response.legacySync, !legacySync.ok {
            warnings.append(
                "Sheet/Reminder sync failed: \(legacySync.error ?? "unknown error")"
            )
        }
        if let surfaceWarning {
            warnings.append(surfaceWarning)
        }
        return warnings.isEmpty ? success : "\(success); \(warnings.joined(separator: "; "))"
    }

    private func perform(_ work: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await work() }
        catch { status = "Couldn't save: \(error.localizedDescription)" }
    }
}
