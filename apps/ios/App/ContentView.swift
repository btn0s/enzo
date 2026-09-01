import SwiftUI
import UIKit

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var composerFocused: Bool
    @State private var pressStartedAt: Date?
    @State private var voiceStartTask: Task<Void, Never>?
    @State private var settingsRoute: SettingsRoute?

    var body: some View {
        NavigationStack {
            ZStack {
                EnzoPalette.canvas.ignoresSafeArea()
                LinearGradient(
                    colors: [
                        EnzoPalette.warmGlow.opacity(0.52),
                        EnzoPalette.canvas.opacity(0.12),
                        EnzoPalette.coolGlow.opacity(0.32),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 18) {
                        nextFeedBanner
                        compactTodayCard
                        recentEvents
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.load() }
            }
            .foregroundStyle(EnzoPalette.ink)
            .navigationTitle("enzo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        settingsRoute = .profile
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 10) {
                composerDock
                    .padding(.horizontal, 14)
                    .padding(.bottom, 5)
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                guard !isRunningUnitTests else { return }
                await model.load()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !isRunningUnitTests else { return }
                Task { await model.load() }
            }
            .onOpenURL { model.handle(url: $0) }
            .sheet(item: $model.editor) { route in
                Group {
                    switch route {
                    case .feed(let draft):
                        FeedEditorView(model: model, draft: draft)
                    case .diaper(let draft):
                        DiaperEditorView(model: model, draft: draft)
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
            }
            .sheet(item: $settingsRoute) { route in
                switch route {
                case .profile:
                    ProfileSettingsView(model: model)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                case .newbornGuide:
                    NewbornGuideSheet(
                        profile: profile,
                        weightKg: model.currentWeightKg,
                        state: model.state
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                case .eventLog:
                    EventLogView(model: model)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
        .tint(EnzoPalette.accent)
    }

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["ENZO_UNIT_TESTING"] == "1"
    }

    private var nextFeedBanner: some View {
        VStack(spacing: 10) {
            Text("NEXT FEED")
                .font(.caption.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(EnzoPalette.accent)

            if let next = model.state?.nextFeedAt {
                TimelineView(.periodic(from: Date.now, by: 1)) { context in
                    if next > context.date {
                        Text(timerInterval: context.date...next, countsDown: true)
                            .contentTransition(.numericText(countsDown: true))
                    } else {
                        Text("Due now")
                            .foregroundStyle(EnzoPalette.attention)
                    }
                }
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)

                Label(
                    next.formatted(date: .omitted, time: .shortened),
                    systemImage: "clock"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(EnzoPalette.muted)
            } else {
                Text("No feed scheduled")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                Text("Log a completed feed to begin the next three-hour window.")
                    .font(.subheadline)
                    .foregroundStyle(EnzoPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 166)
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .background(
            LinearGradient(
                colors: [EnzoPalette.heroStart, EnzoPalette.heroEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 30)
        )
        .shadow(color: .black.opacity(0.055), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.07), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var composerDock: some View {
        if #available(iOS 26.0, *) {
            composerDockContent
                .padding(7)
                .frame(minHeight: 58)
                .glassEffect(
                    .regular.tint(EnzoPalette.glassTint).interactive(),
                    in: .capsule
                )
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        } else {
            composerDockContent
                .padding(7)
                .frame(minHeight: 58)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }

    private var composerDockContent: some View {
        ZStack {
            if model.voice.isListening {
                listeningComposer
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                idleComposer
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.22),
            value: model.voice.isListening
        )
    }

    private var idleComposer: some View {
        HStack(spacing: 3) {
            Menu {
                Button {
                    model.presentNewFeed()
                } label: {
                    Label("Feed", image: "BabyBottle")
                }
                Button {
                    model.presentNewDiaper()
                } label: {
                    Label("Diaper", image: "BabyDiaper")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(ComposerPressStyle())
            .accessibilityLabel("Add manually")

            TextField(
                "",
                text: $model.typedCommand,
                prompt: Text(composerPlaceholder)
                    .foregroundStyle(EnzoPalette.muted.opacity(0.76))
            )
                .font(.body)
                .lineLimit(1)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .focused($composerFocused)
                .frame(height: 44, alignment: .center)
                .onSubmit { sendComposer() }
                .onChange(of: model.voice.transcript) { _, transcript in
                    if model.voice.isListening { model.typedCommand = transcript }
                }
                .accessibilityLabel("Describe what happened")
                .accessibilityIdentifier("commandComposer")

            voiceComposerButton

            if !model.typedCommand.trimmed.isEmpty {
                Button(action: sendComposer) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(EnzoPalette.onAccent)
                        .frame(width: 44, height: 44)
                        .background(EnzoPalette.accent, in: Circle())
                        .contentShape(.circle)
                }
                .buttonStyle(ComposerPressStyle())
                .accessibilityLabel("Send")
                .transition(.opacity.combined(with: .scale(scale: 0.25)))
            }
        }
    }

    private var listeningComposer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.cancelVoice() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(EnzoPalette.controlFill, in: Circle())
                    .contentShape(.circle)
            }
            .buttonStyle(ComposerPressStyle())
            .accessibilityLabel("Cancel dictation")

            ListeningWaveform()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Listening")
                .accessibilityValue(model.voice.transcript)

            Button {
                Task { await model.stopVoiceForReview() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(EnzoPalette.controlFill, in: Circle())
                    .contentShape(.circle)
            }
            .buttonStyle(ComposerPressStyle())
            .accessibilityLabel("Stop dictation")

            Button {
                Task { await model.finishVoice() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(EnzoPalette.onAccent)
                    .frame(width: 44, height: 44)
                    .background(EnzoPalette.accent, in: Circle())
                    .contentShape(.circle)
            }
            .buttonStyle(ComposerPressStyle())
            .accessibilityLabel("Send dictation")
        }
    }

    private var voiceComposerButton: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(model.voice.errorMessage == nil ? EnzoPalette.ink : EnzoPalette.attention)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
            .gesture(voiceGesture)
            .accessibilityLabel("Log by voice")
            .accessibilityHint("Tap to dictate, or hold while speaking")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await model.beginVoice() } }
    }

    private var voiceGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressStartedAt == nil else { return }
                pressStartedAt = Date()
                voiceStartTask = Task { await model.beginVoice() }
            }
            .onEnded { _ in
                let duration = Date().timeIntervalSince(pressStartedAt ?? Date())
                let startTask = voiceStartTask
                pressStartedAt = nil
                voiceStartTask = nil
                guard duration >= 0.35 else {
                    model.status = "Listening"
                    return
                }
                Task {
                    await startTask?.value
                    await model.stopVoiceForReview()
                }
            }
    }

    private var composerPlaceholder: String {
        if model.voice.errorMessage != nil { return "Microphone access needed" }
        if model.isBusy { return "Saving…" }
        return "What happened?"
    }

    private func sendComposer() {
        guard !model.typedCommand.trimmed.isEmpty else { return }
        composerFocused = false
        Task { await model.processTypedCommand() }
    }

    private var compactTodayCard: some View {
        let metrics = todayMetrics

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.title2.weight(.bold))
                Spacer()
                Text("\(Date.now.formatted(.dateTime.month(.abbreviated).day())) · \(DailyInsightBuilder.dayLabel(profile: profile))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(EnzoPalette.muted)
            }

            Divider().overlay(EnzoPalette.divider)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
                ForEach(metrics) { metric in
                    todayMetricRow(metric)
                }
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(EnzoPalette.divider)

            Button {
                settingsRoute = .newbornGuide
            } label: {
                HStack(spacing: 8) {
                    Label("General newborn guide", systemImage: "book.pages.fill")
                    Spacer()
                    Text(DailyInsightBuilder.dayLabel(profile: profile))
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(EnzoPalette.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens today’s feeding and diaper guidance")
        }
        .padding(18)
        .background(EnzoPalette.surface, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.045), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
    }

    private func todayMetricRow(_ metric: TodayMetric) -> some View {
        return GridRow(alignment: .center) {
            MetricGlyph(kind: metric.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EnzoPalette.accent)
                .frame(width: 20)

            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(EnzoPalette.ink)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.value)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("/ \(metric.goal)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(EnzoPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Image(systemName: metric.status.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(metric.status.color)
                .frame(width: 22, alignment: .trailing)
                .accessibilityLabel(metric.status.accessibilityLabel)
        }
        .accessibilityElement(children: .combine)
    }

    private var todayMetrics: [TodayMetric] {
        let day = profile.dayOfLife()
        let state = model.state
        let insights = Dictionary(
            uniqueKeysWithValues: DailyInsightBuilder.make(state: state, profile: profile).map { ($0.id, $0) }
        )
        let feedRange = DailyInsightBuilder.feedRangeForDay(day)
        let wetMinimum = DailyInsightBuilder.wetMinimumForDay(day)
        let dirtyMinimum = DailyInsightBuilder.dirtyMinimumForDay(day)
        let milkReference = DailyInsightBuilder.dailyMilkReference(weightKg: model.currentWeightKg)
        let milkTotal = state?.today.milkMl ?? 0
        let milkStatus = DailyInsightBuilder.dailyMilkStatus(
            totalMl: milkTotal,
            weightKg: model.currentWeightKg,
            day: day
        )
        let feedStatus = insights["feeds"]?.status ?? .referenceOnly
        let wetStatus = insights["wet"]?.status ?? .referenceOnly
        let dirtyStatus = insights["dirty"]?.status ?? .referenceOnly

        return [
            TodayMetric(
                id: "milk",
                title: "Milk",
                icon: .milk,
                value: "\(Int(milkTotal.rounded()))",
                goal: milkReference.map {
                    "\(Int($0.lowerBound.rounded()))–\(Int($0.upperBound.rounded())) mL"
                } ?? "add weight",
                status: milkMetricStatus(
                    status: milkStatus,
                    currentMl: milkTotal,
                    reference: milkReference,
                    day: day
                )
            ),
            TodayMetric(
                id: "feeds",
                title: "Feeds",
                icon: .feeds,
                value: "\(state?.today.feeds ?? 0)",
                goal: "\(Int(feedRange.lowerBound))–\(Int(feedRange.upperBound))",
                status: metricStatus(
                    status: feedStatus,
                    current: state?.today.feeds ?? 0,
                    goal: Int(feedRange.lowerBound)
                )
            ),
            TodayMetric(
                id: "wet",
                title: "Wet",
                icon: .wet,
                value: "\(state?.today.pees ?? 0)",
                goal: wetMinimum.map { "\($0)+" } ?? "—",
                status: metricStatus(
                    status: wetStatus,
                    current: state?.today.pees ?? 0,
                    goal: wetMinimum
                )
            ),
            TodayMetric(
                id: "dirty",
                title: "Dirty",
                icon: .dirty,
                value: "\(state?.today.poops ?? 0)",
                goal: dirtyMinimum.map { "\($0)+" } ?? "—",
                status: metricStatus(
                    status: dirtyStatus,
                    current: state?.today.poops ?? 0,
                    goal: dirtyMinimum
                )
            ),
        ]
    }

    private func metricStatus(
        status: DailyInsight.Status,
        current: Int,
        goal: Int?
    ) -> TodayMetricStatus {
        guard let goal else { return .tracking }
        if current >= goal { return .goalMet }
        return status == .attention ? .belowPace : .onPace
    }

    private func milkMetricStatus(
        status: DailyInsight.Status,
        currentMl: Double,
        reference: ClosedRange<Double>?,
        day: Int
    ) -> TodayMetricStatus {
        guard day >= 7, let reference else { return .tracking }
        if currentMl >= reference.lowerBound { return .goalMet }
        return status == .attention ? .belowPace : .onPace
    }

    private var profile: EnzoProfile {
        EnzoProfile(birthDate: model.birthDate)
    }

    private var recentEvents: some View {
        let events = Array((model.state?.events ?? []).prefix(5))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent")
                    .font(.headline.weight(.bold))
                Spacer()
                if !events.isEmpty {
                    Button("View all") { settingsRoute = .eventLog }
                        .font(.subheadline.weight(.semibold))
                }
            }

            if events.isEmpty {
                Text("Feeds and diapers will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(EnzoPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                ForEach(events) { event in
                    Button {
                        model.presentEditor(for: event)
                    } label: {
                        eventRow(event)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this entry for editing")
                    if event.id != events.last?.id {
                        Divider().overlay(EnzoPalette.divider)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(EnzoPalette.surface, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.04), radius: 12, y: 5)
    }

    private func eventRow(_ event: ServerEvent) -> some View {
        HStack(spacing: 12) {
            EventGlyph(content: event.content)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EnzoPalette.accent)
                .frame(width: 34, height: 34)
                .background(EnzoPalette.accentSoft, in: Circle())

            Text(eventLabel(event))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(event.occurredAt.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(EnzoPalette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private func eventLabel(_ event: ServerEvent) -> String {
        switch event.content {
        case .feed(let feed):
            return feed.amountMl.map { "\(Int($0)) mL \(feed.milkType == .breastMilk ? "breast milk" : "formula")" }
                ?? "\(feed.milkType == .breastMilk ? "Breast milk" : "Formula") feed · amount pending"
        case .diaper(let diaper):
            if diaper.pee && diaper.poop { return "Pee + poop" }
            return diaper.pee ? "Pee" : "Poop"
        }
    }
}

private struct EventLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    @State private var editor: EditorRoute?

    var body: some View {
        NavigationStack {
            List(model.state?.events ?? []) { event in
                Button {
                    editor = route(for: event)
                } label: {
                    HStack(spacing: 12) {
                        EventGlyph(content: event.content)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(EnzoPalette.accent)
                            .frame(width: 34, height: 34)
                            .background(EnzoPalette.accentSoft, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(label(for: event))
                                .font(.subheadline.weight(.semibold))
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(EnzoPalette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EnzoPalette.muted.opacity(0.7))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this entry for editing")
            }
            .scrollContentBackground(.hidden)
            .background(EnzoPalette.canvas)
            .navigationTitle("Entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editor) { route in
                Group {
                    switch route {
                    case .feed(let draft): FeedEditorView(model: model, draft: draft)
                    case .diaper(let draft): DiaperEditorView(model: model, draft: draft)
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
            }
        }
        .tint(EnzoPalette.accent)
    }

    private func route(for event: ServerEvent) -> EditorRoute {
        switch event.content {
        case .feed(let feed):
            var draft = FeedDraft()
            draft.eventID = event.id
            draft.occurredAt = event.occurredAt
            draft.milkType = feed.milkType
            draft.amountMl = feed.amountMl
            draft.notes = event.notes
            draft.resetsTimer = feed.resetsTimer
            return .feed(draft)
        case .diaper(let diaper):
            var draft = DiaperDraft()
            draft.eventID = event.id
            draft.occurredAt = event.occurredAt
            draft.pee = diaper.pee
            draft.poop = diaper.poop
            draft.notes = event.notes
            return .diaper(draft)
        }
    }

    private func label(for event: ServerEvent) -> String {
        switch event.content {
        case .feed(let feed):
            return feed.amountMl.map {
                "\(Int($0)) mL \(feed.milkType == .breastMilk ? "breast milk" : "formula")"
            } ?? "Feed"
        case .diaper(let diaper):
            if diaper.pee && diaper.poop { return "Pee + poop" }
            return diaper.pee ? "Pee" : "Poop"
        }
    }
}

private struct TodayMetric: Identifiable {
    let id: String
    let title: String
    let icon: TodayMetricIcon
    let value: String
    let goal: String
    let status: TodayMetricStatus
}

private enum TodayMetricIcon {
    case milk
    case feeds
    case wet
    case dirty
}

private struct MetricGlyph: View {
    let kind: TodayMetricIcon

    @ViewBuilder
    var body: some View {
        switch kind {
        case .milk:
            BabyBottleGlyph(size: 15)
        case .feeds:
            Image(systemName: "repeat.circle.fill")
        case .wet:
            Image(systemName: "drop.fill")
        case .dirty:
            DiaperGlyph(size: 16)
        }
    }
}

private struct EventGlyph: View {
    let content: EventContent

    @ViewBuilder
    var body: some View {
        switch content {
        case .feed:
            BabyBottleGlyph(size: 17)
        case .diaper:
            DiaperGlyph(size: 17)
        }
    }
}

struct BabyBottleGlyph: View {
    var size: CGFloat = 18

    var body: some View {
        Image("BabyBottle")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size * 0.68, height: size)
            .accessibilityHidden(true)
    }
}

struct DiaperGlyph: View {
    var size: CGFloat = 18

    var body: some View {
        Image("BabyDiaper")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size * 0.86)
            .accessibilityHidden(true)
    }
}

private enum SettingsRoute: String, Identifiable {
    case profile
    case newbornGuide
    case eventLog

    var id: String { rawValue }
}

private enum TodayMetricStatus {
    case belowPace
    case onPace
    case goalMet
    case tracking

    var symbol: String {
        switch self {
        case .belowPace: "arrow.down.circle.fill"
        case .onPace: "arrow.up.circle.fill"
        case .goalMet: "checkmark.circle.fill"
        case .tracking: "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .belowPace: EnzoPalette.attention
        case .onPace, .goalMet: EnzoPalette.success
        case .tracking: EnzoPalette.muted
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .belowPace: "Below pace"
        case .onPace: "On pace"
        case .goalMet: "Goal met"
        case .tracking: "Tracking"
        }
    }
}

private struct ListeningWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
            HStack(spacing: 2.4) {
                ForEach(0..<30, id: \.self) { index in
                    let phase = context.date.timeIntervalSinceReferenceDate * 6.5
                    let wave = (sin(phase + Double(index) * 0.72) + 1) / 2
                    let envelope = sin(Double(index + 1) / 31 * .pi)
                    let height = 4 + (wave * envelope * 17)

                    Capsule()
                        .fill(EnzoPalette.muted.opacity(0.78))
                        .frame(width: 2.4, height: height)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .accessibilityHidden(true)
    }
}

private struct ComposerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

enum EnzoPalette {
    static let canvas = dynamic(light: 0xF6F0E6, dark: 0x171411)
    static let surface = dynamic(light: 0xFFFCF7, dark: 0x24201D).opacity(0.92)
    static let heroStart = dynamic(light: 0xF3D5C5, dark: 0x3B2921)
    static let heroEnd = dynamic(light: 0xF8EEE3, dark: 0x29231F)
    static let warmGlow = dynamic(light: 0xEFBFA8, dark: 0x5A3428)
    static let coolGlow = dynamic(light: 0xDCE8DD, dark: 0x233029)
    static let ink = dynamic(light: 0x221B17, dark: 0xF8F1E8)
    static let muted = dynamic(light: 0x665C55, dark: 0xBFB4A9)
    static let accent = dynamic(light: 0x7B3F2E, dark: 0xE4A184)
    static let onAccent = dynamic(light: 0xFFF9F3, dark: 0x211713)
    static let accentSoft = dynamic(light: 0xF1D9CC, dark: 0x443027)
    static let success = dynamic(light: 0x356C49, dark: 0x7CC894)
    static let attention = dynamic(light: 0x9A3F2C, dark: 0xF2A084)
    static let divider = dynamic(light: 0x2A211C, dark: 0xFFF8F0).opacity(0.11)
    static let controlFill = dynamic(light: 0x2A211C, dark: 0xFFF8F0).opacity(0.10)
    static let glassTint = dynamic(light: 0xFFF7EC, dark: 0x2B2723).opacity(0.20)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
