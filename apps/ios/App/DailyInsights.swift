import Foundation

struct EnzoProfile {
    let birthDate: Date

    static let current = EnzoProfile(
        birthDate: Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 8, day: 28)
        )!
    )

    func dayOfLife(on date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let birthDay = calendar.startOfDay(for: birthDate)
        let currentDay = calendar.startOfDay(for: date)
        return max(1, (calendar.dateComponents([.day], from: birthDay, to: currentDay).day ?? 0) + 1)
    }
}

struct DailyInsight: Identifiable {
    enum Status {
        case onTrack
        case attention
        case referenceOnly
    }

    let id: String
    let title: String
    let value: String
    let detail: String
    let progress: Double?
    let status: Status
}

enum DailyInsightBuilder {
    // General-reference sources encoded by this prototype:
    // CDC: https://www.cdc.gov/infant-toddler-nutrition/formula-feeding/how-much-and-how-often.html
    // AAP: https://www.healthychildren.org/English/ages-stages/baby/formula-feeding/Pages/amount-and-schedule-of-formula-feedings.aspx
    // NHS maternity guidance: https://elht.nhs.uk/application/files/7017/1957/8897/E0126_Early_Bottle_Feeding_V3_Sep23_UNICEF_statement_added_2.pdf
    static func make(
        state: ServerState?,
        profile: EnzoProfile = .current,
        now: Date = Date()
    ) -> [DailyInsight] {
        guard let state else { return [] }
        let day = profile.dayOfLife(on: now)
        let feedRange = feedRangeForDay(day)
        let wetMinimum = wetMinimumForDay(day)
        let dirtyMinimum = dirtyMinimumForDay(day)

        var insights = [
            cadenceInsight(nextFeedAt: state.nextFeedAt, now: now),
            rangeInsight(
                id: "feeds",
                title: "Feeds",
                current: Double(state.today.feeds),
                range: feedRange,
                unit: "",
                now: now
            ),
        ]

        if let latestFormula = state.events.first(where: {
            $0.feed?.milkType == .formula && $0.feed?.amountMl != nil
        }), let amount = latestFormula.feed?.amountMl {
            insights.append(formulaInsight(amountMl: amount, day: day))
        } else {
            insights.append(DailyInsight(
                id: "formula",
                title: "Formula amount",
                value: "No completed bottle yet",
                detail: day <= 7 ? "Typical first-week offer: 30–60 mL" : "Reference needs age and weight",
                progress: nil,
                status: .referenceOnly
            ))
        }

        insights.append(minimumInsight(
            id: "wet",
            title: "Wet diapers",
            current: state.today.pees,
            minimum: wetMinimum,
            now: now
        ))
        insights.append(minimumInsight(
            id: "dirty",
            title: "Dirty diapers",
            current: state.today.poops,
            minimum: dirtyMinimum,
            now: now
        ))
        return insights
    }

    static func dayLabel(profile: EnzoProfile = .current, now: Date = Date()) -> String {
        "Day \(profile.dayOfLife(on: now))"
    }

    private static func cadenceInsight(nextFeedAt: Date?, now: Date) -> DailyInsight {
        guard let nextFeedAt else {
            return DailyInsight(
                id: "cadence",
                title: "Feed cadence",
                value: "Every 3 hours",
                detail: "No next feed scheduled",
                progress: nil,
                status: .attention
            )
        }
        let remaining = nextFeedAt.timeIntervalSince(now)
        return DailyInsight(
            id: "cadence",
            title: "Feed cadence",
            value: "Every 3 hours",
            detail: remaining >= 0 ? "On schedule" : "Feed is overdue",
            progress: nil,
            status: remaining >= 0 ? .onTrack : .attention
        )
    }

    private static func rangeInsight(
        id: String,
        title: String,
        current: Double,
        range: ClosedRange<Double>,
        unit: String,
        now: Date
    ) -> DailyInsight {
        let dayProgress = progressThroughDay(now)
        let expectedMinimum = range.lowerBound * dayProgress
        let onPace = current + 0.5 >= expectedMinimum
        return DailyInsight(
            id: id,
            title: title,
            value: "\(formatted(current)) today • typical \(formatted(range.lowerBound))–\(formatted(range.upperBound))\(unit)",
            detail: onPace ? "Within today’s pace" : "Below today’s pace",
            progress: min(1, current / range.lowerBound),
            status: onPace ? .onTrack : .attention
        )
    }

    private static func formulaInsight(amountMl: Double, day: Int) -> DailyInsight {
        guard day <= 7 else {
            return DailyInsight(
                id: "formula",
                title: "Formula amount",
                value: "Last bottle: \(formatted(amountMl)) mL",
                detail: "Age/weight reference needed",
                progress: nil,
                status: .referenceOnly
            )
        }
        let range = 30.0...60.0
        let inRange = range.contains(amountMl)
        return DailyInsight(
            id: "formula",
            title: "Formula amount",
            value: "Last bottle: \(formatted(amountMl)) mL • typical 30–60 mL",
            detail: inRange ? "Within first-week range" : amountMl < range.lowerBound ? "Below typical single-feed range" : "Above typical single-feed range",
            progress: min(1, amountMl / range.upperBound),
            status: inRange ? .onTrack : .attention
        )
    }

    private static func minimumInsight(
        id: String,
        title: String,
        current: Int,
        minimum: Int?,
        now: Date
    ) -> DailyInsight {
        guard let minimum else {
            return DailyInsight(
                id: id,
                title: title,
                value: "\(current) today",
                detail: "Reference not configured",
                progress: nil,
                status: .referenceOnly
            )
        }
        let expectedMinimum = Double(minimum) * progressThroughDay(now)
        let onPace = Double(current) + 0.5 >= expectedMinimum
        return DailyInsight(
            id: id,
            title: title,
            value: "\(current) today • general minimum \(minimum)",
            detail: onPace ? "Within today’s pace" : "Below today’s pace",
            progress: min(1, Double(current) / Double(minimum)),
            status: onPace ? .onTrack : .attention
        )
    }

    static func feedRangeForDay(_ day: Int) -> ClosedRange<Double> {
        day <= 7 ? 8...12 : 6...8
    }

    static func wetMinimumForDay(_ day: Int) -> Int? {
        switch day {
        case 1: 1
        case 2: 2
        case 3...4: 3
        case 5...6: 5
        case 7...28: 6
        default: nil
        }
    }

    static func dirtyMinimumForDay(_ day: Int) -> Int? {
        day <= 28 ? 1 : nil
    }

    static func dailyMilkReference(weightKg: Double?) -> ClosedRange<Double>? {
        guard let weightKg, weightKg > 0 else { return nil }
        return (weightKg * 150)...(weightKg * 200)
    }

    static func dailyMilkStatus(
        totalMl: Double,
        weightKg: Double?,
        day: Int,
        now: Date = Date()
    ) -> DailyInsight.Status {
        guard day >= 7, let reference = dailyMilkReference(weightKg: weightKg) else {
            return .referenceOnly
        }
        let expectedMinimum = reference.lowerBound * progressThroughDay(now)
        return totalMl + 15 >= expectedMinimum ? .onTrack : .attention
    }

    private static func progressThroughDay(_ now: Date) -> Double {
        let start = Calendar.current.startOfDay(for: now)
        return min(1, max(0, now.timeIntervalSince(start) / 86_400))
    }

    private static func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(1)))
    }
}
