import Foundation

enum Format {
    /// The chosen unit rather than the locale's road units, so a distance
    /// never disagrees with the "/mi" or "/km" on the rate beside it.
    static func distance(_ meters: Double, in unit: DistanceUnit) -> String {
        let converted = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: unit.unitLength)
        return converted.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
        )
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated)
        )
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month().day())
    }

    /// A scheduled time, with the weekday added whenever it doesn't fall on
    /// the operating day the stop is listed under. A drop-off that doesn't
    /// open until the next afternoon, or work that runs past midnight, would
    /// otherwise read as that time on the wrong day.
    static func time(_ date: Date, listedUnder day: Date?, calendar: Calendar = .current) -> String {
        if let day, calendar.isDate(date, inSameDayAs: day) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    static func rate(_ amount: Double, per unit: DistanceUnit) -> String {
        let money = amount.formatted(.currency(code: currencyCode).precision(.fractionLength(2)))
        return "\(money)/\(unit.abbreviation)"
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private static var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }
}
