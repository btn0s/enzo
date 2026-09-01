import Foundation

enum CommandParser {
    static func parse(
        _ transcript: String,
        now: Date = Date(),
        feedDefaultTime: Date? = nil
    ) -> VoiceCommand {
        let text = transcript.lowercased().replacingOccurrences(of: ".", with: "")
        let explicitTime = parsedTime(in: text, relativeTo: now)
        let amount = parsedAmount(in: text)

        let hasPee = text.contains("pee") || text.contains("wet")
        let hasPoop = text.contains("poop") || text.contains("dirty")
        if hasPee || hasPoop {
            var draft = DiaperDraft()
            draft.occurredAt = explicitTime ?? now
            draft.pee = hasPee
            draft.poop = hasPoop
            return .diaper(draft)
        }

        let isFeed = text.contains("feed") || text.contains("feeding") || text.contains("ate") || text.contains("eating")
        guard isFeed else { return .unrecognized }

        var draft = FeedDraft()
        draft.occurredAt = explicitTime ?? feedDefaultTime ?? now
        draft.amountMl = amount
        draft.milkType = text.contains("breast") ? .breastMilk : .formula
        return .feed(draft)
    }

    private static func parsedAmount(in text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(milliliters?|ml|ounces?|oz)"#
        guard let match = firstMatch(pattern, in: text),
              let value = Double(match[1]) else { return nil }
        let unit = match[2]
        return unit.hasPrefix("ounce") || unit == "oz" ? value * 30 : value
    }

    private static func parsedTime(in text: String, relativeTo now: Date) -> Date? {
        let pattern = #"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let match = firstMatch(pattern, in: text),
              var hour = Int(match[1]) else { return nil }
        let minute = Int(match[2]) ?? 0
        let meridiem = match[3]
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }
}
