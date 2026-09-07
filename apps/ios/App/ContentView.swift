import SwiftUI
import UIKit

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsRoute: SettingsRoute?
    @State private var selectedDayOffset = 0

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

                if !model.hasCompletedInitialLoad {
                    DashboardSkeleton(reduceMotion: reduceMotion)
                        .transition(.opacity)
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.25),
                value: model.hasCompletedInitialLoad
            )
            .foregroundStyle(EnzoPalette.ink)
            .navigationTitle("enzo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        settingsRoute = .settings
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "gearshape")
                            if model.alarmWarning != nil {
                                Circle()
                                    .fill(EnzoPalette.attention)
                                    .frame(width: 8, height: 8)
                                    .overlay {
                                        Circle().stroke(EnzoPalette.canvas, lineWidth: 1.5)
                                    }
                                    .offset(x: 3, y: -3)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityLabel(
                        model.alarmWarning == nil
                            ? "Settings"
                            : "Settings, alarm needs attention"
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 10) {
                actionDock
                    .padding(.horizontal, 14)
                    .padding(.bottom, 5)
            }
            .task {
                guard !isRunningUnitTests else { return }
                await model.load()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !isRunningUnitTests else { return }
                Task { await model.load() }
            }
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
                case .settings:
                    SettingsIndexView(model: model)
                        .presentationDetents([.large])
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
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT FEED")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
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
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)

                    Label(
                        "Due \(next.formatted(date: .omitted, time: .shortened))",
                        systemImage: "clock"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EnzoPalette.muted)
                } else {
                    Text("Not scheduled")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text("Log a feed to start the clock")
                        .font(.caption)
                        .foregroundStyle(EnzoPalette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .overlay(EnzoPalette.divider)
                .frame(height: 74)

            bottleTarget
                .frame(width: 104, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(18)
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

    private var bottleTarget: some View {
        let bottle = model.goals().bottleMl

        return VStack(alignment: .leading, spacing: 3) {
            Text("EACH BOTTLE")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(EnzoPalette.accent)

            if let bottle {
                Text("≈ \(model.volumeUnit.format(range: bottle.value))")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(bottle.source.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(EnzoPalette.muted)
            } else {
                Text("Add weight")
                    .font(.subheadline.weight(.semibold))
                Text("in Checkups")
                    .font(.caption2)
                    .foregroundStyle(EnzoPalette.muted)
            }
        }
    }

    @ViewBuilder
    private var actionDock: some View {
        if #available(iOS 26.0, *) {
            actionDockContent
                .padding(7)
                .frame(minHeight: 58)
                .glassEffect(
                    .regular.tint(EnzoPalette.glassTint).interactive(),
                    in: .capsule
                )
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        } else {
            actionDockContent
                .padding(7)
                .frame(minHeight: 58)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }

    private var actionDockContent: some View {
        HStack(spacing: 7) {
            dockButton(title: "Add feed", image: "BabyBottle") {
                model.presentNewFeed()
            }
            dockButton(title: "Add diaper", image: "BabyDiaper") {
                model.presentNewDiaper()
            }
        }
    }

    private func dockButton(
        title: String,
        image: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, image: image)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(EnzoPalette.controlFill, in: Capsule())
                .contentShape(.capsule)
        }
        .buttonStyle(ComposerPressStyle())
        .disabled(model.isBusy)
        .accessibilityLabel(title)
    }

    private var compactTodayCard: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(oldestDayOffset...0, id: \.self) { dayOffset in
                    dailySummaryCard(
                        on: date(forDayOffset: dayOffset),
                        dayOffset: dayOffset
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(dayOffset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: selectedDayBinding)
        .accessibilityAction(named: "Show older day") {
            showOlderDay()
        }
        .accessibilityAction(named: "Show newer day") {
            showNewerDay()
        }
        .onChange(of: oldestDayOffset) { _, oldestOffset in
            if selectedDayOffset < oldestOffset {
                selectedDayOffset = oldestOffset
            }
        }
    }

    private func dailySummaryCard(on date: Date, dayOffset: Int) -> some View {
        let metrics = dashboardMetrics(on: date, dayOffset: dayOffset)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: date, dayOffset: dayOffset))
                        .font(.title2.weight(.bold))
                    Text("\(formattedDate(date)) · Day \(profile.dayOfLife(on: date, calendar: careCalendar))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(EnzoPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

                HStack(spacing: 0) {
                    dayNavigationButton(
                        systemName: "chevron.left",
                        label: "Show older day",
                        disabled: dayOffset <= oldestDayOffset
                    ) {
                        setDayOffset(dayOffset - 1)
                    }
                    dayNavigationButton(
                        systemName: "chevron.right",
                        label: "Show newer day",
                        disabled: dayOffset >= 0
                    ) {
                        setDayOffset(dayOffset + 1)
                    }
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                dailyMetricTile(metrics.feed)
                dailyMetricTile(metrics.milk)
                dailyMetricTile(metrics.pee)
                dailyMetricTile(metrics.poop)
            }
        }
        .padding(18)
        .background(EnzoPalette.surface, in: .rect(cornerRadius: 24))
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.045), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
    }

    private func dailyMetricTile(_ metric: TodayTileMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(EnzoPalette.muted)
                Spacer(minLength: 8)
                Image(systemName: metric.status.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(metric.status.color)
                    .accessibilityLabel(metric.status.accessibilityLabel)
            }

            Text(metric.value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            Text(metric.goal)
                .font(.caption.weight(.medium))
                .foregroundStyle(EnzoPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(EnzoPalette.controlFill, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func dayNavigationButton(
        systemName: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? EnzoPalette.muted.opacity(0.28) : EnzoPalette.accent)
        .disabled(disabled)
        .accessibilityLabel(label)
    }


    private func showOlderDay() {
        setDayOffset(selectedDayOffset - 1)
    }

    private func showNewerDay() {
        setDayOffset(selectedDayOffset + 1)
    }

    private func setDayOffset(_ offset: Int) {
        guard oldestDayOffset...0 ~= offset else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0)) {
            selectedDayOffset = offset
        }
    }

    private var selectedDayBinding: Binding<Int?> {
        Binding(
            get: { selectedDayOffset },
            set: { offset in
                if let offset {
                    selectedDayOffset = offset
                }
            }
        )
    }

    private var careCalendar: Calendar {
        model.state?.careCalendar ?? .current
    }

    private var oldestDayOffset: Int {
        -profile.dayOfLife(on: Date.now, calendar: careCalendar)
    }

    private func date(forDayOffset offset: Int) -> Date {
        let today = careCalendar.startOfDay(for: Date.now)
        return careCalendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func goalReferenceDate(for date: Date, dayOffset: Int) -> Date {
        guard dayOffset < 0,
              let nextDay = careCalendar.date(byAdding: .day, value: 1, to: date) else {
            return Date.now
        }
        return nextDay.addingTimeInterval(-1)
    }

    private func title(for date: Date, dayOffset: Int) -> String {
        switch dayOffset {
        case 0:
            return "Today"
        case -1:
            return "Yesterday"
        default:
            var style = Date.FormatStyle().weekday(.wide)
            style.timeZone = careCalendar.timeZone
            return date.formatted(style)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        var style = Date.FormatStyle().month(.abbreviated).day()
        style.timeZone = careCalendar.timeZone
        return date.formatted(style)
    }

    private func dashboardMetrics(on date: Date, dayOffset: Int) -> TodayDashboardMetrics {
        let summary = model.state?.summary(on: date) ?? .empty
        let goals = model.goals(now: goalReferenceDate(for: date, dayOffset: dayOffset))

        return TodayDashboardMetrics(
            feed: TodayTileMetrics(
                title: "Feeds",
                value: "\(summary.feeds)",
                goal: "Goal \(integerRange(goals.feeds.value))",
                status: dailyStatus(
                    current: Double(summary.feeds),
                    goal: Double(goals.feeds.value.lowerBound),
                    slack: 1,
                    dayOffset: dayOffset
                )
            ),
            milk: TodayTileMetrics(
                title: "Milk",
                value: model.volumeUnit.format(ml: summary.milkMl),
                goal: goals.dailyMilkMl.map {
                    "Goal \(model.volumeUnit.format(range: $0.value))"
                } ?? "Add weight in Checkups",
                status: dailyStatus(
                    current: summary.milkMl,
                    goal: goals.dailyMilkMl.map { $0.value.lowerBound },
                    slack: 30,
                    dayOffset: dayOffset
                )
            ),
            pee: TodayTileMetrics(
                title: "Pee",
                value: "\(summary.pees)",
                goal: goals.peeMin.map { "Goal \($0.value)+" } ?? "Tracking only",
                status: dailyStatus(
                    current: Double(summary.pees),
                    goal: goals.peeMin.map { Double($0.value) },
                    slack: 1,
                    dayOffset: dayOffset
                )
            ),
            poop: TodayTileMetrics(
                title: "Poop",
                value: "\(summary.poops)",
                goal: goals.poopMin.map { "Goal \($0.value)+" } ?? "Tracking only",
                status: dailyStatus(
                    current: Double(summary.poops),
                    goal: goals.poopMin.map { Double($0.value) },
                    slack: 1,
                    dayOffset: dayOffset
                )
            )
        )
    }

    private func dailyStatus(
        current: Double,
        goal: Double?,
        slack: Double,
        dayOffset: Int
    ) -> PaceStatus {
        if dayOffset < 0 {
            return DailyReference.completion(current: current, goal: goal)
        }
        return DailyReference.pace(
            current: current,
            goal: goal,
            slack: slack,
            calendar: careCalendar
        )
    }

    private func integerRange(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)–\(range.upperBound)"
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
            return feed.amountMl.map {
                "\(model.volumeUnit.format(ml: $0)) \(feed.milkType == .breastMilk ? "breast milk" : "formula")"
            } ?? "\(feed.milkType == .breastMilk ? "Breast milk" : "Formula") feed · amount pending"
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
                    editor = EditorRoute(event: event)
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

    private func label(for event: ServerEvent) -> String {
        switch event.content {
        case .feed(let feed):
            return feed.amountMl.map {
                "\(model.volumeUnit.format(ml: $0)) \(feed.milkType == .breastMilk ? "breast milk" : "formula")"
            } ?? "Feed"
        case .diaper(let diaper):
            if diaper.pee && diaper.poop { return "Pee + poop" }
            return diaper.pee ? "Pee" : "Poop"
        }
    }
}

private struct TodayDashboardMetrics {
    let feed: TodayTileMetrics
    let milk: TodayTileMetrics
    let pee: TodayTileMetrics
    let poop: TodayTileMetrics
}

private struct TodayTileMetrics {
    let title: String
    let value: String
    let goal: String
    let status: PaceStatus
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


private enum SettingsRoute: Identifiable {
    case settings
    case eventLog

    var id: String {
        switch self {
        case .settings: "settings"
        case .eventLog: "event-log"
        }
    }
}

private extension PaceStatus {
    var symbol: String {
        switch self {
        case .belowPace: "arrow.down.circle.fill"
        case .onPace: "clock.fill"
        case .goalMet: "checkmark.circle.fill"
        case .goalNotMet: "xmark.circle.fill"
        case .tracking: "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .belowPace, .goalNotMet: EnzoPalette.attention
        case .goalMet: EnzoPalette.success
        case .onPace, .tracking: EnzoPalette.muted
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .belowPace: "Below pace"
        case .onPace: "On pace"
        case .goalMet: "Goal met"
        case .goalNotMet: "Goal not met"
        case .tracking: "Tracking"
        }
    }
}

private struct DashboardSkeleton: View {
    let reduceMotion: Bool
    @State private var pulses = false

    var body: some View {
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
                VStack(spacing: 18) {
                    skeletonHero
                    skeletonToday
                    skeletonRecent
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
            .scrollDisabled(true)
        }
        .opacity(reduceMotion ? 1 : (pulses ? 0.72 : 1))
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulses = true
            }
        }
    }

    private var skeletonHero: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                skeletonLine(width: 74, height: 9)
                skeletonLine(width: 150, height: 38)
                skeletonLine(width: 108, height: 11)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                skeletonLine(width: 82, height: 9)
                skeletonLine(width: 74, height: 22)
                skeletonLine(width: 62, height: 9)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(18)
        .background(
            LinearGradient(
                colors: [EnzoPalette.heroStart, EnzoPalette.heroEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 30)
        )
    }

    private var skeletonToday: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                skeletonLine(width: 78, height: 24)
                Spacer()
                skeletonLine(width: 104, height: 12)
            }
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 9) {
                        skeletonLine(width: 52, height: 11)
                        skeletonLine(width: 66, height: 25)
                        skeletonLine(width: 84, height: 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(EnzoPalette.controlFill, in: .rect(cornerRadius: 18))
                }
            }
            skeletonLine(width: 164, height: 12)
                .padding(.vertical, 12)
        }
        .padding(18)
        .background(EnzoPalette.surface, in: .rect(cornerRadius: 24))
    }

    private var skeletonRecent: some View {
        VStack(alignment: .leading, spacing: 14) {
            skeletonLine(width: 76, height: 18)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 17)
                        .fill(EnzoPalette.controlFill)
                        .frame(width: 34, height: 34)
                    skeletonLine(width: 126, height: 12)
                    Spacer()
                    skeletonLine(width: 48, height: 11)
                }
            }
        }
        .padding(18)
        .background(EnzoPalette.surface, in: .rect(cornerRadius: 24))
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(EnzoPalette.controlFill)
            .frame(width: width, height: height)
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
