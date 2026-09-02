import Foundation

/// Display unit for milk volumes. The server always stores milliliters.
/// Shared with the widget extension so widgets format the same way.
enum VolumeUnit: String, Codable, CaseIterable, Identifiable {
    case ounces
    case milliliters

    static let millilitersPerOunce = 29.573_5

    var id: String { rawValue }
    var symbol: String { self == .ounces ? "oz" : "mL" }
    var label: String { self == .ounces ? "Ounces" : "Milliliters" }

    /// Common bottle sizes offered as one-tap presets, in this unit.
    var presets: [Double] {
        switch self {
        case .ounces: [1, 1.5, 2, 2.5, 3]
        case .milliliters: [30, 45, 60, 75, 90]
        }
    }

    func value(fromMl ml: Double) -> Double {
        self == .ounces ? ml / Self.millilitersPerOunce : ml
    }

    func ml(from value: Double) -> Double {
        self == .ounces ? value * Self.millilitersPerOunce : value
    }

    /// Number only, e.g. "2.5" or "75".
    func number(ml: Double) -> String {
        let value = self.value(fromMl: ml)
        switch self {
        case .ounces: return value.formatted(.number.precision(.fractionLength(0...1)))
        case .milliliters: return String(Int(value.rounded()))
        }
    }

    /// Number with symbol, e.g. "2.5 oz" or "75 mL".
    func format(ml: Double) -> String {
        "\(number(ml: ml)) \(symbol)"
    }

    /// "340 mL" for a point value, "510–680 mL" for a range.
    func format(range: ClosedRange<Double>) -> String {
        range.lowerBound == range.upperBound
            ? format(ml: range.lowerBound)
            : "\(number(ml: range.lowerBound))–\(number(ml: range.upperBound)) \(symbol)"
    }
}
