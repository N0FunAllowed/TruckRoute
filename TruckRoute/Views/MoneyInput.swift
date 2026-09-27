import Foundation

/// Reading and pre-filling money typed into a form, in the user's own locale.
///
/// Both directions live here so they always agree. The form used to
/// pre-fill with the locale's number format but read back by keeping only
/// digits and ".", so wherever "." groups thousands and "," marks decimals
/// (Germany, French Canada, Mexico…), $2,400 pre-filled as "2.400" and
/// saved back as $2.40 — on any edit, even one that never touched the rate.
enum MoneyInput {
    /// What a field shows for an amount already saved. No grouping, so
    /// nothing in it can be misread on the way back in.
    static func text(for amount: Double, locale: Locale = .current) -> String {
        amount.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0...2))
                .locale(locale)
        )
    }

    /// The amount typed into a field, or nil if nothing was, or if it isn't
    /// one number (two decimal separators, say) — rather than a guess.
    ///
    /// Only digits and the locale's decimal separator count. Currency
    /// symbols, spaces and grouping separators are decoration, so "$2,400.50"
    /// in the US and "2.400,50 €" in Germany both read as 2400.5.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let decimalSeparator = locale.decimalSeparator ?? "."
        var normalized = ""
        for character in text {
            if let digit = character.wholeNumberValue, (0...9).contains(digit) {
                normalized.append(String(digit))
            } else if String(character) == decimalSeparator {
                guard !normalized.contains(".") else { return nil }
                normalized.append(".")
            }
        }
        guard normalized.contains(where: \.isWholeNumber) else { return nil }
        return Double(normalized)
    }
}
