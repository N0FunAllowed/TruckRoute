import XCTest
@testable import TruckRoute

final class FormatTests: XCTestCase {
    /// Fixed UTC so "which day is this" can't shift with the runner's zone.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
    }

    func testATimeOnTheDayItIsListedUnderIsJustTheTime() {
        let arrival = date(day: 1, hour: 14)
        XCTAssertEqual(
            Format.time(arrival, listedUnder: date(day: 1, hour: 0), calendar: calendar),
            arrival.formatted(date: .omitted, time: .shortened)
        )
    }

    /// A stop listed under Monday that the truck reaches on Tuesday must not
    /// read as Monday at that time.
    func testATimeOnAnotherDaySaysWhichDay() {
        let arrival = date(day: 2, hour: 14)
        XCTAssertNotEqual(
            Format.time(arrival, listedUnder: date(day: 1, hour: 0), calendar: calendar),
            arrival.formatted(date: .omitted, time: .shortened)
        )
    }

    /// The yard at the end of the route has no day of its own to be read
    /// against, so its time always says which day.
    func testATimeWithNoDayToReadAgainstSaysWhichDay() {
        let arrival = date(day: 1, hour: 14)
        XCTAssertNotEqual(
            Format.time(arrival, listedUnder: nil, calendar: calendar),
            arrival.formatted(date: .omitted, time: .shortened)
        )
    }
}
