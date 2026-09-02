import Foundation

struct EnzoProfile {
    let birthDate: Date

    /// Calendar days since the birth date. The birth day itself is day 0, so a
    /// baby born Friday night is on day 1 for all of Saturday.
    func dayOfLife(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: birthDate),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        return max(0, days)
    }

    func hoursOfAge(at date: Date = Date()) -> Double {
        max(0, date.timeIntervalSince(birthDate) / 3600)
    }
}

enum PaceStatus {
    case belowPace
    case onPace
    case goalMet
    case tracking
}

enum GoalSource: Hashable {
    case guidance
    case checkup(Checkup)

    var isClinician: Bool {
        if case .checkup = self { return true }
        return false
    }

    /// "Dr., Sep 4" or "Guidance".
    var label: String {
        switch self {
        case .guidance: "Guidance"
        case .checkup(let checkup): "Dr., \(checkup.occurredAt.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}

struct Goal<Value: Hashable>: Hashable {
    let value: Value
    let source: GoalSource
    /// What guidance would say, when a checkup overrides it.
    let guidance: Value?
}

/// Today's targets after applying the active checkup on top of guidance.
struct DailyGoals {
    let feeds: Goal<ClosedRange<Int>>
    let feedIntervalMinutes: Goal<Int>
    let dailyMilkMl: Goal<ClosedRange<Double>>?
    let bottleMl: Goal<ClosedRange<Double>>?
    let peeMin: Goal<Int>?
    let poopMin: Goal<Int>?
    let weightKg: Double?

    static func resolve(
        checkup: Checkup?,
        weightKg: Double?,
        day: Int,
        hoursOfAge: Double,
        defaultIntervalMinutes: Int
    ) -> DailyGoals {
        func pick<V: Hashable>(_ override: V?, guidance: V?) -> Goal<V>? {
            if let override, let checkup {
                return Goal(value: override, source: .checkup(checkup), guidance: guidance)
            }
            return guidance.map { Goal(value: $0, source: .guidance, guidance: nil) }
        }

        let guidedFeeds = DailyReference.feedRange(day: day)
        let feedsOverride: ClosedRange<Int>? = {
            guard let checkup, checkup.feedsMin != nil || checkup.feedsMax != nil else { return nil }
            let lower = checkup.feedsMin ?? min(guidedFeeds.lowerBound, checkup.feedsMax!)
            let upper = checkup.feedsMax ?? max(guidedFeeds.upperBound, lower)
            return lower...upper
        }()
        let feeds = pick(feedsOverride, guidance: guidedFeeds)!

        let guidedMilk = DailyReference.dailyMilk(weightKg: weightKg, hoursOfAge: hoursOfAge)
        let milkOverride: ClosedRange<Double>? = {
            guard let checkup, checkup.milkMlMin != nil || checkup.milkMlMax != nil else { return nil }
            let lower = checkup.milkMlMin ?? checkup.milkMlMax!
            let upper = checkup.milkMlMax ?? lower
            return lower...upper
        }()
        let dailyMilk = pick(milkOverride, guidance: guidedMilk)

        // Guidance per bottle: today's daily volume spread over the low end of
        // the feed range, so an 8-feed day at 340 mL is about 43 mL a bottle.
        let guidedBottle = guidedMilk.map { milk in
            let feedsPerDay = Double(guidedFeeds.lowerBound)
            return (milk.lowerBound / feedsPerDay)...(milk.upperBound / feedsPerDay)
        }
        let bottle = pick(checkup?.bottleMl.map { $0...$0 }, guidance: guidedBottle)

        return DailyGoals(
            feeds: feeds,
            feedIntervalMinutes: pick(checkup?.feedIntervalMinutes, guidance: defaultIntervalMinutes)!,
            dailyMilkMl: dailyMilk,
            bottleMl: bottle,
            peeMin: pick(checkup?.peeMin, guidance: DailyReference.wetMinimum(day: day)),
            poopMin: pick(checkup?.poopMin, guidance: DailyReference.dirtyMinimum(day: day)),
            weightKg: weightKg
        )
    }
}

/// General-reference goals and the pacing math behind the Today card.
///
/// Sources:
/// - CDC, formula feeding how much and how often (8–12 feeds, every 2–3 h in the first weeks):
///   https://www.cdc.gov/infant-toddler-nutrition/formula-feeding/how-much-and-how-often.html
/// - AAP, amount and schedule of formula feedings (about 150–200 mL/kg/day once established):
///   https://www.healthychildren.org/English/ages-stages/baby/formula-feeding/Pages/amount-and-schedule-of-formula-feedings.aspx
/// - Safer Care Victoria, formula volumes for term neonates by hours of age:
///   https://www.safercare.vic.gov.au/best-practice-improvement/clinical-guidance/neonatal/formula-feeding
/// - East Lancashire NHS, early bottle-feeding nappy chart by day of life:
///   https://elht.nhs.uk/application/files/7017/1957/8897/E0126_Early_Bottle_Feeding_V3_Sep23_UNICEF_statement_added_2.pdf
enum DailyReference {
    /// Feeds per 24 hours. Every 3 hours is 8; every 2 hours is 12.
    static func feedRange(day: Int) -> ClosedRange<Int> {
        day <= 7 ? 8...12 : 6...8
    }

    static func wetMinimum(day: Int) -> Int? {
        switch day {
        case 0...1: 1
        case 2: 2
        case 3...4: 3
        case 5...6: 5
        case 7...28: 6
        default: nil
        }
    }

    static func dirtyMinimum(day: Int) -> Int? {
        day <= 28 ? 1 : nil
    }

    /// Term-neonate formula volume, mL per kg per 24 hours, by hours of age.
    static func milkPerKg(hoursOfAge: Double) -> ClosedRange<Double> {
        switch hoursOfAge {
        case ..<24: 30...30
        case ..<48: 60...60
        case ..<72: 80...80
        case ..<96: 100...100
        case ..<120: 120...120
        case ..<144: 150...150
        default: 150...200
        }
    }

    /// Daily milk goal in mL, or nil until a weight is set.
    static func dailyMilk(weightKg: Double?, hoursOfAge: Double) -> ClosedRange<Double>? {
        guard let weightKg, weightKg > 0 else { return nil }
        let perKg = milkPerKg(hoursOfAge: hoursOfAge)
        return (perKg.lowerBound * weightKg)...(perKg.upperBound * weightKg)
    }

    /// Compares today's count against the goal, scaled by how far through the
    /// day it is. `slack` absorbs the fact that events arrive in discrete steps.
    static func pace(
        current: Double,
        goal: Double?,
        slack: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PaceStatus {
        guard let goal else { return .tracking }
        if current >= goal { return .goalMet }
        let expected = goal * progressThroughDay(now, calendar: calendar)
        return current + slack >= expected ? .onPace : .belowPace
    }

    private static func progressThroughDay(_ now: Date, calendar: Calendar) -> Double {
        let start = calendar.startOfDay(for: now)
        return min(1, max(0, now.timeIntervalSince(start) / 86_400))
    }
}
