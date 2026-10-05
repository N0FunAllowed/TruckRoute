import CoreLocation
import XCTest
@testable import TruckRoute

final class RouteOrderingTests: XCTestCase {
    /// A fixed UTC calendar, for the same reason `RouteSchedulerTests` pins
    /// one: the opening-hour grouping these tests exercise is calendar work,
    /// and `.current` would make the results depend on where CI runs.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var baseDay: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDay)!
    }

    /// Degrees of latitude from the yard. One degree is roughly 111 km, so
    /// these are far enough apart that nearest-neighbor has an obvious answer.
    private let yard = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    private func north(_ degrees: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: degrees, longitude: 0)
    }

    private func load(
        opens: Date,
        pickup: CLLocationCoordinate2D,
        dropoff: CLLocationCoordinate2D? = nil
    ) -> OrderableLoad {
        OrderableLoad(pickupOpens: opens, pickup: pickup, dropoff: dropoff ?? pickup)
    }

    private func order(_ loads: [OrderableLoad]) -> [Int] {
        RouteOrdering.order(loads, from: yard, calendar: calendar)
    }

    // MARK: - Distance still decides when nothing says otherwise

    func testWithoutTimeIntentTheNearestPickupGoesFirst() {
        let loads = [
            load(opens: at(8), pickup: north(5)),
            load(opens: at(8), pickup: north(1)),
            load(opens: at(8), pickup: north(3)),
        ]

        XCTAssertEqual(order(loads), [1, 2, 0])
    }

    /// The common case: loads typed in one sitting carry whatever minute they
    /// were entered. Those are not a dispatcher's instructions, so geography
    /// should still decide.
    func testPickupsOpeningInTheSameHourAreOrderedByDistance() {
        let loads = [
            load(opens: at(8, 55), pickup: north(5)),
            load(opens: at(8, 10), pickup: north(1)),
            load(opens: at(8, 30), pickup: north(3)),
        ]

        XCTAssertEqual(order(loads), [1, 2, 0])
    }

    /// The truck is wherever the last load was dropped, not where it picked it
    /// up. Load 0 starts beside the yard and ends 10 north, so the pickup at 11
    /// north is next — ordering from the pickup instead would wrongly take the
    /// one at 2 north.
    func testOrderingContinuesFromTheLastDropoffNotItsPickup() {
        let loads = [
            load(opens: at(8), pickup: north(1), dropoff: north(10)),
            load(opens: at(8), pickup: north(11)),
            load(opens: at(8), pickup: north(2)),
        ]

        XCTAssertEqual(order(loads), [0, 1, 2])
    }

    // MARK: - An earlier opening beats a closer pickup

    /// The bug this ordering exists to fix: nearest-neighbor alone takes the
    /// 14:00 pickup sitting next to the yard first, idles six hours, and runs
    /// the 08:00 load that evening.
    func testAnEarlierPickupIsWorkedBeforeACloserLaterOne() {
        let loads = [
            load(opens: at(14), pickup: north(1)),
            load(opens: at(8), pickup: north(8)),
        ]

        XCTAssertEqual(order(loads), [1, 0])
    }

    func testOpeningTimeOrdersAcrossSeveralWaves() {
        let loads = [
            load(opens: at(16), pickup: north(1)),
            load(opens: at(8), pickup: north(9)),
            load(opens: at(12), pickup: north(5)),
        ]

        XCTAssertEqual(order(loads), [1, 2, 0])
    }

    /// Distance only breaks ties *within* a wave — it never promotes a load
    /// out of a later one.
    func testDistanceOnlyBreaksTiesInsideTheEarliestWave() {
        let loads = [
            load(opens: at(8), pickup: north(9)),
            load(opens: at(8), pickup: north(7)),
            load(opens: at(9), pickup: north(1)),
        ]

        XCTAssertEqual(order(loads), [1, 0, 2])
    }

    // MARK: - Edges

    func testAnEmptyDayOrdersToNothing() {
        XCTAssertEqual(order([]), [])
    }

    func testASingleLoadIsItsOwnOrder() {
        XCTAssertEqual(order([load(opens: at(8), pickup: north(4))]), [0])
    }

    func testEveryLoadIsOrderedExactlyOnce() {
        let loads = (0..<8).map {
            load(opens: at(8 + $0 % 3), pickup: north(Double($0) + 1))
        }

        XCTAssertEqual(order(loads).sorted(), Array(0..<8))
    }
}
