import XCTest
@testable import TruckRoute

final class MoneyInputTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")
    private let france = Locale(identifier: "fr_FR")

    func testUSAmountsIgnoreTheDollarSignAndThousandsSeparators() throws {
        XCTAssertEqual(try XCTUnwrap(MoneyInput.parse("$2,400.50", locale: us)), 2400.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(MoneyInput.parse("2400", locale: us)), 2400, accuracy: 0.001)
    }

    /// Where "," marks decimals, "." groups thousands, so "2.400,50" is two
    /// thousand four hundred and a half, not two point four.
    func testCommaDecimalLocalesReadTheCommaAsTheDecimal() throws {
        XCTAssertEqual(try XCTUnwrap(MoneyInput.parse("2.400,50", locale: germany)), 2400.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(MoneyInput.parse("2400,5 €", locale: germany)), 2400.5, accuracy: 0.001)
    }

    /// The bug this replaces: editing a saved load pre-filled its rate in the
    /// locale's format and read it back as US digits, so $2,400 became $2.40
    /// in Germany on any save. Whatever `text(for:)` shows must read back as
    /// the same amount.
    func testAPrefilledAmountReadsBackUnchanged() throws {
        for locale in [us, germany, france] {
            for amount in [0, 2400, 2400.5, 1_234_567.89] {
                let text = MoneyInput.text(for: amount, locale: locale)
                let parsed = try XCTUnwrap(
                    MoneyInput.parse(text, locale: locale),
                    "\(locale.identifier) couldn't read back \"\(text)\""
                )
                XCTAssertEqual(parsed, amount, accuracy: 0.001, "\(locale.identifier) via \"\(text)\"")
            }
        }
    }

    func testNothingTypedIsNoAmount() {
        XCTAssertNil(MoneyInput.parse("", locale: us))
        XCTAssertNil(MoneyInput.parse("   ", locale: us))
        XCTAssertNil(MoneyInput.parse("$", locale: us))
    }

    /// Two decimal separators isn't one number. Refusing it lets the form
    /// say so, rather than saving a guess.
    func testTextThatIsNotOneNumberIsRefused() {
        XCTAssertNil(MoneyInput.parse("1.2.3", locale: us))
        XCTAssertNil(MoneyInput.parse("1,2,3", locale: germany))
        XCTAssertNil(MoneyInput.parse("abc", locale: us))
    }
}
