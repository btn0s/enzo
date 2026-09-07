import Foundation
import SwiftUI
import UIKit

struct FeedEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    @State private var draft: FeedDraft
    @State private var unit: VolumeUnit
    /// Amount as entered, in `unit`. Converted to mL on save.
    @State private var amount: Double?
    @State private var confirmsDeletion = false
    @FocusState private var amountFocused: Bool

    init(model: AppModel, draft: FeedDraft) {
        self.model = model
        _draft = State(initialValue: draft)
        _unit = State(initialValue: model.volumeUnit)
        _amount = State(initialValue: draft.amountMl.map(model.volumeUnit.value(fromMl:)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    amountRow
                    presetRow
                } footer: {
                    if let bottle = model.goals().bottleMl {
                        Text("Plan: ≈ \(unit.format(range: bottle.value)) per bottle · \(bottle.source.label)")
                    }
                }

                Section {
                    Picker("Milk", selection: $draft.milkType) {
                        ForEach(MilkType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("When") {
                        DatePicker("", selection: $draft.occurredAt)
                            .labelsHidden()
                    }
                }

                Section {
                    Toggle("Set next-feed alarm", isOn: $draft.resetsTimer)
                } footer: {
                    Text("Turn this off for a top-up. The feed is saved without moving the countdown, Live Activity, or feed alarm.")
                }

                if draft.eventID != nil {
                    Section {
                        Button("Delete entry", role: .destructive) { confirmsDeletion = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled((amount ?? 0) <= 0)
                }
            }
            .task {
                if draft.eventID == nil { amountFocused = true }
            }
            .confirmationDialog(
                "Delete this feed?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete feed", role: .destructive) { deleteEntry() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            TextField("0", value: $amount, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .focused($amountFocused)

            Menu {
                Picker("Unit", selection: $unit) {
                    ForEach(VolumeUnit.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(unit.symbol)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.headline)
                .foregroundStyle(EnzoPalette.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(EnzoPalette.accentSoft, in: Capsule())
            }
            .onChange(of: unit) { old, new in
                guard let current = amount else { return }
                amount = new.value(fromMl: old.ml(from: current))
            }
        }
        .padding(.vertical, 6)
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(unit.presets, id: \.self) { preset in
                let selected = amount == preset
                Button {
                    amount = preset
                    amountFocused = false
                } label: {
                    Text(preset.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            selected ? EnzoPalette.accent : EnzoPalette.controlFill,
                            in: Capsule()
                        )
                        .foregroundStyle(selected ? EnzoPalette.onAccent : EnzoPalette.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.formatted()) \(unit.symbol)")
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
    }

    private var title: String { draft.eventID == nil ? "Log feed" : "Edit feed" }

    private func save() {
        guard let amount, amount > 0 else { return }
        var saved = draft
        saved.amountMl = unit.ml(from: amount)
        Task {
            await model.saveFeed(saved)
            dismiss()
        }
    }

    private func deleteEntry() {
        guard let eventID = draft.eventID else { return }
        Task {
            await model.deleteEvent(id: eventID)
            dismiss()
        }
    }
}

struct DiaperEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    @State private var draft: DiaperDraft
    @State private var confirmsDeletion = false

    init(model: AppModel, draft: DiaperDraft) {
        self.model = model
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        tile("Pee", systemImage: "drop.fill", isOn: $draft.pee)
                        tile("Poop", isOn: $draft.poop)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section {
                    LabeledContent("When") {
                        DatePicker("", selection: $draft.occurredAt)
                            .labelsHidden()
                    }
                }


                if draft.eventID != nil {
                    Section {
                        Button("Delete entry", role: .destructive) { confirmsDeletion = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(draft.eventID == nil ? "Log diaper" : "Edit diaper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.saveDiaper(draft)
                            dismiss()
                        }
                    }
                    .disabled(!draft.pee && !draft.poop)
                }
            }
            .confirmationDialog(
                "Delete this diaper?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete diaper", role: .destructive) { deleteEntry() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func deleteEntry() {
        guard let eventID = draft.eventID else { return }
        Task {
            await model.deleteEvent(id: eventID)
            dismiss()
        }
    }

    /// Large toggle tile. Uses the SF Symbol when given, otherwise the diaper glyph.
    private func tile(
        _ title: String,
        systemImage: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        let selected = isOn.wrappedValue
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.wrappedValue.toggle() }
        } label: {
            VStack(spacing: 10) {
                Group {
                    if let systemImage {
                        Image(systemName: systemImage)
                    } else {
                        DiaperGlyph(size: 30)
                    }
                }
                .font(.system(size: 30, weight: .semibold))
                .frame(height: 34)

                HStack(spacing: 5) {
                    Text(title)
                        .font(.headline)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .foregroundStyle(selected ? EnzoPalette.onAccent : EnzoPalette.accent)
            .background(
                selected ? EnzoPalette.accent : EnzoPalette.accentSoft,
                in: .rect(cornerRadius: 20)
            )
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum SettingsDestination: String, CaseIterable, Identifiable {
    case profile
    case checkups
    case feedSchedule
    case volume
    case alarms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .checkups: "Checkups"
        case .feedSchedule: "Feed schedule"
        case .volume: "Volume"
        case .alarms: "Alarms"
        }
    }


    var symbol: String {
        switch self {
        case .profile: "person.crop.circle.fill"
        case .checkups: "stethoscope"
        case .feedSchedule: "clock.arrow.circlepath"
        case .volume: "scalemass.fill"
        case .alarms: "alarm.fill"
        }
    }
}

struct SettingsIndexView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("Enzo") {
                    destinationRow(.profile)
                    destinationRow(.checkups)
                }

                Section("Preferences") {
                    destinationRow(.feedSchedule)
                    destinationRow(.volume)
                    destinationRow(.alarms)
                }
            }
            .scrollContentBackground(.hidden)
            .background(EnzoPalette.canvas)
            .foregroundStyle(EnzoPalette.ink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsDestination.self) { destination in
                SettingsDetailView(model: model, destination: destination)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(EnzoPalette.accent)
    }

    private func destinationRow(_ destination: SettingsDestination) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EnzoPalette.accent)
                    .frame(width: 34, height: 34)
                    .background(EnzoPalette.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(.body.weight(.medium))
                    Text(detail(for: destination))
                        .font(.caption)
                        .foregroundStyle(EnzoPalette.muted)
                        .lineLimit(2)
                }

                if destination == .alarms, model.alarmWarning != nil {
                    Spacer(minLength: 8)
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(EnzoPalette.attention)
                        .accessibilityLabel("Needs attention")
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
    }

    private func detail(for destination: SettingsDestination) -> String {
        switch destination {
        case .profile:
            "Day \(model.profile.dayOfLife()) · \(model.birthDate.formatted(date: .abbreviated, time: .omitted))"
        case .checkups:
            "\(model.state?.checkups.count ?? 0) recorded"
        case .feedSchedule:
            FeedIntervalFormatting.label(for: model.defaultFeedIntervalMinutes)
        case .volume:
            model.volumeUnit.label
        case .alarms:
            model.alarmsEnabled
                ? "\(model.alarmCadence.title) · \(model.alarmSound.title)"
                : "Off"
        }
    }
}

struct SettingsDetailView: View {
    @Bindable var model: AppModel
    let destination: SettingsDestination
    @State private var birthDraft: Date
    @State private var checkupRoute: CheckupRoute?
    @State private var leadDraft = ""
    @State private var intervalDraft: Int
    @FocusState private var leadFocused: Bool

    init(model: AppModel, destination: SettingsDestination) {
        self.model = model
        self.destination = destination
        _birthDraft = State(initialValue: model.birthDate)
        _intervalDraft = State(initialValue: model.defaultFeedIntervalMinutes)
    }

    var body: some View {
        Form {
            selectedSection
        }
        .scrollContentBackground(.hidden)
        .background(EnzoPalette.canvas)
        .foregroundStyle(EnzoPalette.ink)
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $checkupRoute) { route in
            CheckupEditorView(
                model: model,
                checkup: route.checkup,
                isNew: route.isNew
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        }
        .onAppear {
            leadDraft = String(model.alarmLeadMinutes)
            intervalDraft = model.defaultFeedIntervalMinutes
        }
        .onDisappear {
            if destination == .alarms {
                commitLeadDraft()
            }
        }
        .onChange(of: model.alarmLeadMinutes) { _, minutes in
            guard !leadFocused else { return }
            leadDraft = String(minutes)
        }
        .onChange(of: leadFocused) { _, focused in
            guard !focused else { return }
            commitLeadDraft()
        }
        .onChange(of: intervalDraft) { _, minutes in
            Task {
                await model.saveFeedIntervalMinutes(minutes)
                intervalDraft = model.defaultFeedIntervalMinutes
            }
        }
        .onChange(of: model.defaultFeedIntervalMinutes) { _, minutes in
            guard intervalDraft != minutes else { return }
            intervalDraft = minutes
        }
        .tint(EnzoPalette.accent)
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch destination {
        case .profile:
            profileSection
        case .checkups:
            checkupsSection
        case .feedSchedule:
            feedScheduleSection
        case .volume:
            volumeSection
        case .alarms:
            alarmsSection
        }
    }

    private var profileSection: some View {
        Section {
            DatePicker(
                "Born",
                selection: $birthDraft,
                in: ...Date.now,
                displayedComponents: [.date, .hourAndMinute]
            )

            LabeledContent("Day of life") {
                Text("Day \(EnzoProfile(birthDate: birthDraft).dayOfLife())")
                    .foregroundStyle(EnzoPalette.muted)
            }

            if birthDraft != model.birthDate {
                Button {
                    Task { await model.saveBirthDate(birthDraft) }
                } label: {
                    Label("Save birthday", systemImage: "checkmark.circle.fill")
                }
                .disabled(model.isBusy)
            }
        } header: {
            Text("Profile")
        }
    }

    private var checkupsSection: some View {
        Section {
            if checkups.isEmpty {
                ContentUnavailableView(
                    "No checkups yet",
                    systemImage: "stethoscope",
                    description: Text("Add a visit to record weight or a clinician’s instructions.")
                )
            } else {
                ForEach(checkups) { checkup in
                    Button {
                        checkupRoute = .edit(checkup)
                    } label: {
                        checkupRow(checkup)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                checkupRoute = .add(Checkup.new())
            } label: {
                Label("Add checkup", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Checkups")
        } footer: {
            Text("The latest completed checkup supplies weight and any clinician-set goals.")
        }
    }

    private var volumeSection: some View {
        Section("Volume") {
            Picker("Display unit", selection: $model.volumeUnit) {
                ForEach(VolumeUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var feedScheduleSection: some View {
        Section {
            Picker("Feed interval", selection: $intervalDraft) {
                ForEach(FeedIntervalFormatting.options, id: \.self) { minutes in
                    Text(FeedIntervalFormatting.label(for: minutes)).tag(minutes)
                }
            }
            .disabled(model.isBusy)

            if let checkupInterval = model.state?.activeCheckup?.feedIntervalMinutes {
                LabeledContent("Currently in use") {
                    Text(FeedIntervalFormatting.label(for: checkupInterval))
                        .foregroundStyle(EnzoPalette.muted)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Feed schedule")
        } footer: {
            if model.state?.activeCheckup?.feedIntervalMinutes != nil {
                Text("The active checkup’s interval is currently in use. Clear it from that checkup to use this setting.")
            } else {
                Text("The next-feed countdown and alarm are due this long after a timer-resetting feed.")
            }
        }
    }

    private var alarmsSection: some View {
        Group {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: alarmStatus.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(alarmStatus.color)
                        .frame(width: 36, height: 36)
                        .background(alarmStatus.color.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(alarmStatus.title)
                            .font(.subheadline.weight(.semibold))
                        Text(alarmStatus.detail)
                            .font(.caption)
                            .foregroundStyle(EnzoPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)

                Toggle("Feed alarms", isOn: alarmsEnabledBinding)

                if let alarmWarning = model.alarmWarning {
                    Text(alarmWarning)
                        .font(.caption)
                        .foregroundStyle(EnzoPalette.attention)
                        .fixedSize(horizontal: false, vertical: true)

                    if alarmPermissionDenied {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        } label: {
                            Label("Open iPhone Settings", systemImage: "gearshape.fill")
                        }
                    }
                }
            } header: {
                Text("Alarms")
            } footer: {
                Text("Alarm settings are stored only on this iPhone. Other phones keep their own alarm settings.")
            }

            Section {
                LabeledContent("Alarm before due") {
                    HStack(spacing: 6) {
                        TextField("0", text: $leadDraft)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 54)
                            .focused($leadFocused)
                            .accessibilityLabel("Minutes before feed due")
                        Text("min")
                            .foregroundStyle(EnzoPalette.muted)
                    }
                }

                Picker("Cadence", selection: alarmCadenceBinding) {
                    ForEach(AlarmCadence.allCases) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }

                Picker("Sound", selection: alarmSoundBinding) {
                    ForEach(AlarmSound.allCases) { sound in
                        Text(sound.title).tag(sound)
                    }
                }

                Button {
                    Task { await model.testAlarm() }
                } label: {
                    Label("Test selected sound in 10 seconds", systemImage: "alarm.waves.left.and.right")
                }
                .disabled(model.isBusy)

                if let message = model.alarmTestMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(EnzoPalette.success)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Behavior")
            } footer: {
                Text(alarmCadenceFooter)
            }

            Section {
                Toggle("Limit alarm hours", isOn: alarmActiveHoursEnabledBinding)

                if model.alarmActiveHoursEnabled {
                    DatePicker(
                        "From",
                        selection: alarmActiveHoursStartBinding,
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        "Until",
                        selection: alarmActiveHoursEndBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Active hours")
            } footer: {
                Text("Outside this range Enzo stays silent. Overnight ranges, such as 8 PM–7 AM, are supported.")
            }
        }
    }

    private var alarmsEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.alarmsEnabled },
            set: { enabled in
                Task { await model.setAlarmsEnabled(enabled) }
            }
        )
    }

    private var alarmCadenceBinding: Binding<AlarmCadence> {
        Binding(
            get: { model.alarmCadence },
            set: { cadence in
                Task { await model.setAlarmCadence(cadence) }
            }
        )
    }

    private var alarmSoundBinding: Binding<AlarmSound> {
        Binding(
            get: { model.alarmSound },
            set: { sound in
                Task { await model.setAlarmSound(sound) }
            }
        )
    }

    private var alarmActiveHoursEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.alarmActiveHoursEnabled },
            set: { enabled in
                Task { await model.setAlarmActiveHoursEnabled(enabled) }
            }
        )
    }

    private var alarmActiveHoursStartBinding: Binding<Date> {
        Binding(
            get: { alarmTime(for: model.alarmActiveHoursStartMinutes) },
            set: { date in
                Task { await model.setAlarmActiveHours(startMinutes: alarmMinutes(from: date)) }
            }
        )
    }

    private var alarmActiveHoursEndBinding: Binding<Date> {
        Binding(
            get: { alarmTime(for: model.alarmActiveHoursEndMinutes) },
            set: { date in
                Task { await model.setAlarmActiveHours(endMinutes: alarmMinutes(from: date)) }
            }
        )
    }

    private var alarmCadenceFooter: String {
        if let minutes = model.alarmCadence.repeatMinutes {
            return "Remind me schedules the next alert exactly \(minutes) minutes later. Acknowledge ends the alarm."
        }
        return "The alarm rings once. Acknowledge it and it stays off until another feed starts the timer."
    }

    private func alarmTime(for minutes: Int) -> Date {
        Calendar.current.date(
            byAdding: .minute,
            value: minutes,
            to: Calendar.current.startOfDay(for: Date())
        )!
    }

    private func alarmMinutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func commitLeadDraft() {
        let parsed = Int(leadDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? model.alarmLeadMinutes
        let clamped = AlarmLeadFormatting.clamp(parsed)
        leadDraft = String(clamped)
        Task { await model.setAlarmLeadMinutes(clamped) }
    }

    private var checkups: [Checkup] {
        (model.state?.checkups ?? []).sorted { $0.occurredAt > $1.occurredAt }
    }

    private func checkupRow(_ checkup: Checkup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(EnzoPalette.accent)
                .frame(width: 34, height: 34)
                .background(EnzoPalette.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(checkup.occurredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold))

                    if checkup.id == model.state?.activeCheckupId {
                        Text("ACTIVE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.7)
                            .foregroundStyle(EnzoPalette.success)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(EnzoPalette.success.opacity(0.12), in: Capsule())
                    }
                }

                Text(checkupSummary(checkup))
                    .font(.caption)
                    .foregroundStyle(EnzoPalette.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(EnzoPalette.muted.opacity(0.7))
                .padding(.top, 10)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this checkup for editing")
    }

    private func checkupSummary(_ checkup: Checkup) -> String {
        var parts: [String] = []
        if let weightKg = checkup.weightKg {
            parts.append(WeightFormat.display(weightKg))
        }
        if checkup.hasOverrides {
            parts.append("Clinician goals")
        }
        if !checkup.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Notes")
        }
        return parts.isEmpty ? "No measurements or instructions" : parts.joined(separator: " · ")
    }

    private var alarmPermissionDenied: Bool {
        guard let warning = model.alarmWarning?.lowercased() else { return false }
        return warning.contains("permission")
            || warning.contains("denied")
            || warning.contains("enable alarms")
    }

    private var alarmStatus: (title: String, detail: String, symbol: String, color: Color) {
        if !model.alarmsEnabled {
            return (
                "Off",
                "Feed alarms are disabled on this iPhone.",
                "alarm.slash.fill",
                EnzoPalette.muted
            )
        }
        if model.alarmWarning != nil {
            return (
                "Needs attention",
                "Enzo could not schedule the feed alarm.",
                "exclamationmark.triangle.fill",
                EnzoPalette.attention
            )
        }
        if model.currentFeedAlarmAcknowledged {
            return (
                "Acknowledged",
                "This feed alarm stays off until another feed starts the next-feed timer.",
                "checkmark.circle.fill",
                EnzoPalette.success
            )
        }
        if let nextFeedAt = model.state?.nextFeedAt,
           let trigger = model.feedAlarmTrigger() {
            let lead = model.alarmLeadMinutes == 0
                ? "at feed time"
                : "\(model.alarmLeadMinutes) min before feed"
            return (
                "Scheduled",
                "\(trigger.formatted(date: .omitted, time: .shortened)), \(lead). Feed due \(nextFeedAt.formatted(date: .omitted, time: .shortened)).",
                "alarm.fill",
                EnzoPalette.success
            )
        }
        if model.alarmActiveHoursEnabled, model.state?.nextFeedAt != nil {
            return (
                "Silenced",
                "The next feed alarm falls outside your active hours.",
                "moon.zzz.fill",
                EnzoPalette.muted
            )
        }
        return (
            "Waiting",
            "Log a feed with its alarm enabled to schedule the next alarm.",
            "clock.fill",
            EnzoPalette.muted
        )
    }
}

private enum CheckupRoute: Identifiable {
    case add(Checkup)
    case edit(Checkup)

    var id: String {
        switch self {
        case .add(let checkup): "add-\(checkup.id)"
        case .edit(let checkup): "edit-\(checkup.id)"
        }
    }

    var checkup: Checkup {
        switch self {
        case .add(let checkup), .edit(let checkup): checkup
        }
    }

    var isNew: Bool {
        if case .add = self { return true }
        return false
    }
}

private enum WeightFormat {
    static let poundsPerKilogram = 2.204_622_621_8

    enum Unit: String, CaseIterable, Identifiable {
        case imperial = "lb + oz"
        case metric = "kg"

        var id: String { rawValue }
    }

    static func display(_ kilograms: Double) -> String {
        let components = imperialComponents(kilograms)
        let ounces = components.ounces.formatted(
            .number.precision(.fractionLength(0...1))
        )
        return "\(components.pounds) lb \(ounces) oz"
    }

    static func imperialComponents(_ kilograms: Double) -> (pounds: Int, ounces: Double) {
        let totalPounds = kilograms * poundsPerKilogram
        let pounds = Int(totalPounds.rounded(.down))
        return (pounds, (totalPounds - Double(pounds)) * 16)
    }

    static func kilograms(pounds: Int, ounces: Double) -> Double {
        (Double(pounds) + ounces / 16) / poundsPerKilogram
    }
}

struct CheckupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    let isNew: Bool

    @State private var draft: Checkup
    @State private var weightUnit: WeightFormat.Unit = .imperial
    @State private var pounds: Int?
    @State private var ounces: Double?
    @State private var kilograms: Double?
    @State private var bottleAmount: Double?
    @State private var milkMinimum: Double?
    @State private var milkMaximum: Double?
    @State private var confirmsDeletion = false

    init(model: AppModel, checkup: Checkup, isNew: Bool) {
        self.model = model
        self.isNew = isNew
        _draft = State(initialValue: checkup)

        if let kilograms = checkup.weightKg {
            let components = WeightFormat.imperialComponents(kilograms)
            _pounds = State(initialValue: components.pounds)
            _ounces = State(initialValue: components.ounces)
            _kilograms = State(initialValue: kilograms)
        } else {
            _pounds = State(initialValue: nil)
            _ounces = State(initialValue: nil)
            _kilograms = State(initialValue: nil)
        }

        _bottleAmount = State(
            initialValue: checkup.bottleMl.map(model.volumeUnit.value(fromMl:))
        )
        _milkMinimum = State(
            initialValue: checkup.milkMlMin.map(model.volumeUnit.value(fromMl:))
        )
        _milkMaximum = State(
            initialValue: checkup.milkMlMax.map(model.volumeUnit.value(fromMl:))
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                visitSection
                weightSection
                instructionsSection
                notesSection

                if !isNew {
                    Section {
                        Button("Delete checkup", role: .destructive) {
                            confirmsDeletion = true
                        }
                        .disabled(model.isBusy)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(EnzoPalette.canvas)
            .foregroundStyle(EnzoPalette.ink)
            .navigationTitle(isNew ? "Add checkup" : "Edit checkup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(validationMessage != nil || model.isBusy)
                }
            }
            .confirmationDialog(
                "Delete this checkup?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete checkup", role: .destructive) { deleteCheckup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Later checkups will continue to determine today’s goals.")
            }
            .onChange(of: weightUnit) { oldUnit, newUnit in
                convertWeight(from: oldUnit, to: newUnit)
            }
        }
        .tint(EnzoPalette.accent)
    }

    private var visitSection: some View {
        Section("Visit") {
            DatePicker(
                "Date and time",
                selection: $draft.occurredAt,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }

    private var weightSection: some View {
        Section {
            Picker("Weight unit", selection: $weightUnit) {
                ForEach(WeightFormat.Unit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            if weightUnit == .imperial {
                LabeledContent("Weight") {
                    HStack(spacing: 7) {
                        TextField("—", value: $pounds, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                        Text("lb")
                            .foregroundStyle(EnzoPalette.muted)
                        TextField(
                            "—",
                            value: $ounces,
                            format: .number.precision(.fractionLength(0...1))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        Text("oz")
                            .foregroundStyle(EnzoPalette.muted)
                    }
                }
            } else {
                LabeledContent("Weight") {
                    HStack(spacing: 7) {
                        TextField(
                            "—",
                            value: $kilograms,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 84)
                        Text("kg")
                            .foregroundStyle(EnzoPalette.muted)
                    }
                }
            }

            if let weightError {
                Text(weightError)
                    .font(.caption)
                    .foregroundStyle(EnzoPalette.attention)
            }
        } header: {
            Text("Measurement")
        } footer: {
            Text("Weight is optional and is used to calculate general milk guidance.")
        }
    }

    private var instructionsSection: some View {
        Section {
            optionalDoubleField(
                "Each bottle",
                value: $bottleAmount,
                suffix: model.volumeUnit.symbol
            )

            optionalIntField(
                "Feed interval",
                value: $draft.feedIntervalMinutes,
                suffix: "min",
                placeholder: "Settings"
            )

            LabeledContent("Feeds per day") {
                integerRangeFields(
                    minimum: $draft.feedsMin,
                    maximum: $draft.feedsMax,
                    suffix: ""
                )
            }

            LabeledContent("Milk per day") {
                decimalRangeFields(
                    minimum: $milkMinimum,
                    maximum: $milkMaximum,
                    suffix: model.volumeUnit.symbol
                )
            }

            optionalIntField("Pee per day", value: $draft.peeMin, suffix: "min")
            optionalIntField("Poop per day", value: $draft.poopMin, suffix: "min")

            if let instructionsError {
                Text(instructionsError)
                    .font(.caption)
                    .foregroundStyle(EnzoPalette.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Doctor’s instructions")
        } footer: {
            Text("Leave Feed interval blank to use Settings; other blank fields use Guidance. A single end of a range is allowed, and Enzo completes it with the closest reference value.")
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional visit notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3...7)
        }
    }

    private func optionalIntField(
        _ title: String,
        value: Binding<Int?>,
        suffix: String,
        placeholder: String = "Guidance"
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 7) {
                TextField(placeholder, value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 92)
                Text(suffix)
                    .foregroundStyle(EnzoPalette.muted)
            }
        }
    }

    private func optionalDoubleField(
        _ title: String,
        value: Binding<Double?>,
        suffix: String
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 7) {
                TextField(
                    "Guidance",
                    value: value,
                    format: .number.precision(.fractionLength(0...1))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 92)
                Text(suffix)
                    .foregroundStyle(EnzoPalette.muted)
            }
        }
    }

    private func integerRangeFields(
        minimum: Binding<Int?>,
        maximum: Binding<Int?>,
        suffix: String
    ) -> some View {
        HStack(spacing: 6) {
            TextField("Min", value: minimum, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
            Text("–")
                .foregroundStyle(EnzoPalette.muted)
            TextField("Max", value: maximum, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
            if !suffix.isEmpty {
                Text(suffix)
                    .foregroundStyle(EnzoPalette.muted)
            }
        }
    }

    private func decimalRangeFields(
        minimum: Binding<Double?>,
        maximum: Binding<Double?>,
        suffix: String
    ) -> some View {
        HStack(spacing: 6) {
            TextField(
                "Min",
                value: minimum,
                format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 48)
            Text("–")
                .foregroundStyle(EnzoPalette.muted)
            TextField(
                "Max",
                value: maximum,
                format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 48)
            Text(suffix)
                .foregroundStyle(EnzoPalette.muted)
        }
    }

    private var weightIsBlank: Bool {
        switch weightUnit {
        case .imperial: pounds == nil && ounces == nil
        case .metric: kilograms == nil
        }
    }

    private var enteredWeightKg: Double? {
        switch weightUnit {
        case .imperial:
            guard pounds != nil || ounces != nil else { return nil }
            return WeightFormat.kilograms(
                pounds: pounds ?? 0,
                ounces: ounces ?? 0
            )
        case .metric:
            return kilograms
        }
    }

    private var weightError: String? {
        guard !weightIsBlank else { return nil }
        if weightUnit == .imperial, let ounces, !(0..<16).contains(ounces) {
            return "Ounces must be from 0 up to 15.9."
        }
        guard let weight = enteredWeightKg, (0.5...30).contains(weight) else {
            return "Enter a weight between 0.5 and 30 kg."
        }
        return nil
    }

    private var instructionsError: String? {
        let positiveInts = [
            draft.feedIntervalMinutes,
            draft.feedsMin,
            draft.feedsMax,
            draft.peeMin,
            draft.poopMin,
        ]
        if positiveInts.compactMap({ $0 }).contains(where: { $0 <= 0 }) {
            return "Instruction values must be greater than zero."
        }

        let positiveVolumes = [bottleAmount, milkMinimum, milkMaximum]
        if positiveVolumes.compactMap({ $0 }).contains(where: { $0 <= 0 }) {
            return "Milk amounts must be greater than zero."
        }

        if let minimum = draft.feedsMin,
           let maximum = draft.feedsMax,
           minimum > maximum {
            return "The minimum feeds per day cannot exceed the maximum."
        }

        if let minimum = milkMinimum,
           let maximum = milkMaximum,
           minimum > maximum {
            return "The minimum daily milk cannot exceed the maximum."
        }

        return nil
    }

    private var validationMessage: String? {
        weightError ?? instructionsError
    }

    private func convertWeight(from oldUnit: WeightFormat.Unit, to newUnit: WeightFormat.Unit) {
        guard oldUnit != newUnit else { return }
        switch (oldUnit, newUnit) {
        case (.imperial, .metric):
            guard pounds != nil || ounces != nil else {
                kilograms = nil
                return
            }
            kilograms = WeightFormat.kilograms(
                pounds: pounds ?? 0,
                ounces: ounces ?? 0
            )
        case (.metric, .imperial):
            guard let kilograms else {
                pounds = nil
                ounces = nil
                return
            }
            let components = WeightFormat.imperialComponents(kilograms)
            pounds = components.pounds
            ounces = components.ounces
        default:
            break
        }
    }

    private func save() {
        guard validationMessage == nil else { return }
        var checkup = draft
        checkup.weightKg = enteredWeightKg
        checkup.bottleMl = bottleAmount.map(model.volumeUnit.ml(from:))
        checkup.milkMlMin = milkMinimum.map(model.volumeUnit.ml(from:))
        checkup.milkMlMax = milkMaximum.map(model.volumeUnit.ml(from:))

        Task {
            await model.saveCheckup(checkup, isNew: isNew)
            dismiss()
        }
    }

    private func deleteCheckup() {
        Task {
            await model.deleteCheckup(id: draft.id)
            dismiss()
        }
    }
}


enum AlarmLeadFormatting {
    static func label(for minutes: Int) -> String {
        minutes == 0 ? "At due time" : "\(minutes) min before due"
    }

    static func clamp(_ minutes: Int) -> Int {
        Swift.min(Swift.max(minutes, AlarmTriggerCalculator.leadRange.lowerBound), AlarmTriggerCalculator.leadRange.upperBound)
    }
}
