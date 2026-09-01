import Foundation
import SwiftUI

struct FeedEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    @State private var draft: FeedDraft
    @State private var showsOptions = false
    @State private var confirmsDeletion = false
    @FocusState private var amountFocused: Bool

    init(model: AppModel, draft: FeedDraft) {
        self.model = model
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Milk", selection: $draft.milkType) {
                        ForEach(MilkType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Amount") {
                        TextField("mL", value: $draft.amountMl, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                            .frame(maxWidth: 110)
                    }

                    LabeledContent("When") {
                        DatePicker("", selection: $draft.occurredAt)
                            .labelsHidden()
                    }
                }

                Section {
                    DisclosureGroup("More options", isExpanded: $showsOptions) {
                        TextField("Notes", text: $draft.notes, axis: .vertical)
                        Toggle("Set next feed alarm", isOn: $draft.resetsTimer)
                    }
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
                        .disabled((draft.amountMl ?? 0) <= 0)
                }
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

    private var title: String { draft.eventID == nil ? "Log feed" : "Edit feed" }

    private func save() {
        Task {
            await model.saveFeed(draft)
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
                Section("What was in it?") {
                    checkbox("Pee", isOn: $draft.pee)
                    checkbox("Poop", isOn: $draft.poop)
                }

                Section {
                    LabeledContent("When") {
                        DatePicker("", selection: $draft.occurredAt)
                            .labelsHidden()
                    }
                    TextField("Optional note", text: $draft.notes, axis: .vertical)
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

    private func checkbox(
        _ title: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                DiaperGlyph()
                    .foregroundStyle(EnzoPalette.accent)
                Text(title)
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.title3)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? "Selected" : "Not selected")
    }
}

struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    @State private var weightDraft: WeightUpdateDraft?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Birthday",
                        selection: $model.birthDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )

                    LabeledContent("Current weight") {
                        Text(weightDescription)
                            .foregroundStyle(model.currentWeightKg == nil ? .secondary : .primary)
                    }

                    if let updatedAt = model.weightUpdatedAt {
                        LabeledContent("Updated") {
                            Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        weightDraft = WeightUpdateDraft(currentKg: model.currentWeightKg)
                    } label: {
                        Label("Update current weight", systemImage: "scalemass.fill")
                    }
                } header: {
                    Text("Enzo")
                } footer: {
                    Text("Weight is used for the general daily milk reference. During the first week, the app tracks volume without judging pace.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(EnzoPalette.canvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $weightDraft) { draft in
                WeightEditorView(model: model, initialWeightKg: draft.currentKg)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var weightDescription: String {
        guard let kilograms = model.currentWeightKg else { return "Not set" }
        let totalPounds = kilograms * 2.204_622_621_8
        let pounds = Int(totalPounds.rounded(.down))
        let ounces = (totalPounds - Double(pounds)) * 16
        return "\(pounds) lb \(ounces.formatted(.number.precision(.fractionLength(0...1)))) oz"
    }
}

struct NewbornGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: EnzoProfile
    let weightKg: Double?
    let state: ServerState?

    private var day: Int { profile.dayOfLife() }
    private var today: TodaySummary? { state?.today }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    guideHeader
                    guidanceCard
                    clinicianNote
                    sourceLinks
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(EnzoPalette.canvas)
            .navigationTitle("Newborn guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(EnzoPalette.accent)
    }

    private var guideHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DAY \(day)")
                .font(.caption.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(EnzoPalette.accent)

            Text("A quick read on today")
                .font(.title2.weight(.bold))

            Text("General reference for \(Date.now.formatted(.dateTime.month(.wide).day())). Enzo’s own pattern and care team matter more than any single number.")
                .font(.subheadline)
                .foregroundStyle(EnzoPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var guidanceCard: some View {
        VStack(spacing: 0) {
            NewbornGuideRow(
                icon: .feeds,
                title: "Feeds",
                current: "\(today?.feeds ?? 0) today",
                reference: feedReference,
                detail: feedDetail
            )
            guideDivider
            NewbornGuideRow(
                icon: .milk,
                title: "Milk",
                current: "\(formatted(today?.milkMl ?? 0)) mL today",
                reference: milkReference,
                detail: milkDetail
            )
            guideDivider
            NewbornGuideRow(
                icon: .wet,
                title: "Wet diapers",
                current: "\(today?.pees ?? 0) today",
                reference: minimumReference(DailyInsightBuilder.wetMinimumForDay(day)),
                detail: wetDetail
            )
            guideDivider
            NewbornGuideRow(
                icon: .dirty,
                title: "Dirty diapers",
                current: "\(today?.poops ?? 0) today",
                reference: minimumReference(DailyInsightBuilder.dirtyMinimumForDay(day)),
                detail: dirtyDetail
            )
        }
        .background(EnzoPalette.surface, in: .rect(cornerRadius: 22))
    }

    private var guideDivider: some View {
        Divider()
            .overlay(EnzoPalette.divider)
            .padding(.leading, 62)
    }

    private var clinicianNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "cross.case.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(EnzoPalette.accent)
                .frame(width: 30, height: 30)
                .background(EnzoPalette.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Clinician guidance wins")
                    .font(.subheadline.weight(.semibold))
                Text("If Enzo is difficult to wake, feeds poorly, seems increasingly jaundiced, or his diaper output drops, contact his pediatrician or maternity team.")
                    .font(.caption)
                    .foregroundStyle(EnzoPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(EnzoPalette.accentSoft.opacity(0.62), in: .rect(cornerRadius: 18))
    }

    private var sourceLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCES")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(EnzoPalette.muted)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                sourceLink(
                    "Formula: how much and how often",
                    organization: "CDC",
                    url: "https://www.cdc.gov/infant-toddler-nutrition/formula-feeding/how-much-and-how-often.html"
                )
                guideDivider
                sourceLink(
                    "Amount and schedule of formula feedings",
                    organization: "American Academy of Pediatrics",
                    url: "https://www.healthychildren.org/english/ages-stages/baby/formula-feeding/pages/amount-and-schedule-of-formula-feedings.aspx"
                )
                guideDivider
                sourceLink(
                    "Formula milk: common questions",
                    organization: "NHS",
                    url: "https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/bottle-feeding/formula-milk-questions/"
                )
                guideDivider
                sourceLink(
                    "Early bottle-feeding days",
                    organization: "East Lancashire NHS",
                    url: "https://elht.nhs.uk/services/maternity-and-newborn-services/infant-feeding/early-bottle-feeding-days"
                )
            }
            .background(EnzoPalette.surface, in: .rect(cornerRadius: 18))
        }
    }

    private func sourceLink(_ title: String, organization: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(EnzoPalette.ink)
                        .multilineTextAlignment(.leading)
                    Text(organization)
                        .font(.caption)
                        .foregroundStyle(EnzoPalette.muted)
                }
                Spacer(minLength: 10)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EnzoPalette.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var feedReference: String {
        let range = DailyInsightBuilder.feedRangeForDay(day)
        return "\(formatted(range.lowerBound))–\(formatted(range.upperBound)) in 24 hours"
    }

    private var feedDetail: String {
        day <= 7
            ? "In the first days, most formula-fed newborns eat every 2–3 hours. Follow hunger and fullness cues."
            : "Timing and appetite vary. Follow hunger and fullness cues and Enzo’s clinician guidance."
    }

    private var milkReference: String {
        if day <= 7 { return "Often 30–60 mL per feed" }
        guard let range = DailyInsightBuilder.dailyMilkReference(weightKg: weightKg) else {
            return "Add weight in Settings"
        }
        return "About \(formatted(range.lowerBound))–\(formatted(range.upperBound)) mL per day"
    }

    private var milkDetail: String {
        day <= 7
            ? "Early bottle sizes are a loose reference, not a quota. The app does not score daily milk pace during the first week."
            : "The weight-based daily range is a general reference. Appetite can vary from feed to feed."
    }

    private var wetDetail: String {
        switch day {
        case 1: "At least one wet diaper is a common day-one reference."
        case 2: "Wet diapers should begin increasing as feeding becomes established."
        case 3...4: "Urine output should keep increasing; diapers should feel heavier."
        default: "After the first several days, around six wet diapers a day is a common reference."
        }
    }

    private var dirtyDetail: String {
        day <= 4
            ? "At least one stool is a common early reference, with color changing from dark meconium over the first days."
            : "Stool frequency varies. A change from Enzo’s established pattern matters more than a single count."
    }

    private func minimumReference(_ minimum: Int?) -> String {
        minimum.map { "\($0)+ in 24 hours" } ?? "No simple daily target"
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value
            ? String(Int(value))
            : value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct NewbornGuideRow: View {
    enum Icon {
        case feeds
        case milk
        case wet
        case dirty
    }

    let icon: Icon
    let title: String
    let current: String
    let reference: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            glyph
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EnzoPalette.accent)
                .frame(width: 34, height: 34)
                .background(EnzoPalette.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(current)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(EnzoPalette.muted)
                }

                Text(reference)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(EnzoPalette.ink)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(EnzoPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .feeds:
            Image(systemName: "repeat.circle.fill")
        case .milk:
            BabyBottleGlyph(size: 17)
        case .wet:
            Image(systemName: "drop.fill")
        case .dirty:
            DiaperGlyph(size: 17)
        }
    }
}

private struct WeightUpdateDraft: Identifiable {
    let id = UUID()
    let currentKg: Double?
}

private struct WeightEditorView: View {
    enum Unit: String, CaseIterable, Identifiable {
        case imperial = "lb + oz"
        case metric = "kg"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let model: AppModel
    @State private var unit: Unit
    @State private var pounds: Int?
    @State private var ounces: Double?
    @State private var kilograms: Double?
    @FocusState private var focusedField: Field?

    private enum Field { case pounds, ounces, kilograms }

    init(model: AppModel, initialWeightKg: Double?) {
        self.model = model
        _unit = State(initialValue: .imperial)

        if let initialWeightKg {
            let totalPounds = initialWeightKg * 2.204_622_621_8
            let wholePounds = Int(totalPounds.rounded(.down))
            _pounds = State(initialValue: wholePounds)
            _ounces = State(initialValue: (totalPounds - Double(wholePounds)) * 16)
            _kilograms = State(initialValue: initialWeightKg)
        } else {
            _pounds = State(initialValue: nil)
            _ounces = State(initialValue: nil)
            _kilograms = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Unit", selection: $unit) {
                        ForEach(Unit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)

                    if unit == .imperial {
                        LabeledContent("Weight") {
                            HStack(spacing: 8) {
                                TextField("0", value: $pounds, format: .number)
                                    .focused($focusedField, equals: .pounds)
                                    .frame(width: 54)
                                Text("lb").foregroundStyle(.secondary)
                                TextField("0", value: $ounces, format: .number.precision(.fractionLength(0...1)))
                                    .focused($focusedField, equals: .ounces)
                                    .frame(width: 54)
                                Text("oz").foregroundStyle(.secondary)
                            }
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        }
                    } else {
                        LabeledContent("Weight") {
                            HStack(spacing: 8) {
                                TextField("0", value: $kilograms, format: .number.precision(.fractionLength(0...2)))
                                    .focused($focusedField, equals: .kilograms)
                                    .frame(width: 90)
                                Text("kg").foregroundStyle(.secondary)
                            }
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(EnzoPalette.canvas)
            .navigationTitle("Current weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(enteredKilograms == nil)
                }
            }
            .task {
                focusedField = unit == .imperial ? .pounds : .kilograms
            }
            .onChange(of: unit) { _, newUnit in
                focusedField = newUnit == .imperial ? .pounds : .kilograms
            }
        }
    }

    private var enteredKilograms: Double? {
        let value: Double?
        switch unit {
        case .imperial:
            guard let pounds else { return nil }
            value = (Double(pounds) + (ounces ?? 0) / 16) / 2.204_622_621_8
        case .metric:
            value = kilograms
        }
        guard let value, (0.5...30).contains(value) else { return nil }
        return value
    }

    private func save() {
        guard let enteredKilograms else { return }
        model.updateCurrentWeight(kilograms: enteredKilograms)
        dismiss()
    }
}
