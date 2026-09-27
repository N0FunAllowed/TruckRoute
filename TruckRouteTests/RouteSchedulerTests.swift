import CoreLocation
import XCTest
@testable import TruckRoute

final class RouteSchedulerTests: XCTestCase {
    /// A fixed UTC calendar rather than `.current`. These tests assert on
    /// absolute times built by adding hours, so a daylight-saving boundary
    /// would otherwise shift a wall-clock expectation by an hour twice a
    /// year, and a suite that happened to run across midnight could pick up
    /// two different "today"s within one test.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    private let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    private var baseDay: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let targetDay = calendar.date(byAdding: .day, value: day, to: baseDay)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay)!
    }

    /// Always schedules against the fixed calendar above.
    private func schedule(_ stops: [RouteStop]) -> [RouteStop] {
        RouteScheduler.schedule(stops, calendar: calendar)
    }

    private func stop(
        _ kind: StopKind,
        day: Date? = nil,
        windowStart: Date? = nil,
        deadline: Date? = nil,
        serviceDurationMinutes: Int = 0,
        travelTime: TimeInterval? = nil
    ) -> RouteStop {
        var stop = RouteStop(
            kind: kind,
            placeName: "Somewhere",
            address: "1 Main St",
            coordinate: coordinate,
            loadReference: nil,
            day: day,
            loadRate: nil,
            windowStart: windowStart,
            deadline: deadline,
            serviceDurationMinutes: serviceDurationMinutes
        )
        stop.travelTime = travelTime
        return stop
    }

    // MARK: Future first pickup

    func testAFuturePickupIsScheduledOnItsOwnDayNotToday() throws {
        let pickupDay = date(5, 0)
        let windowStart = date(5, 10)
        let stops = [
            stop(.start),
            stop(.pickup, day: pickupDay, windowStart: windowStart, travelTime: 3600),
        ]

        let scheduled = schedule(stops)

        // The yard start never got a day, so it never got a schedule either.
        XCTAssertNil(scheduled[0].scheduledArrival)

        let arrival = try XCTUnwrap(scheduled[1].scheduledArrival)
        XCTAssertEqual(arrival, windowStart)
        XCTAssertTrue(calendar.isDate(arrival, inSameDayAs: pickupDay))
    }

    func testADayWithNoEarlyWindowStartsAtTheDefaultDayStartHourPlusTravel() throws {
        let pickupDay = date(2, 0)
        let stops = [
            stop(.start),
            stop(.pickup, day: pickupDay, travelTime: 1800), // 30 min to the first stop.
        ]

        let scheduled = schedule(stops)
        let arrival = try XCTUnwrap(scheduled[1].scheduledArrival)
        XCTAssertEqual(arrival, date(2, RouteScheduler.defaultDayStartHour, 30))
    }

    // MARK: Multi-day routes

    func testASecondDayResetsTheClockRatherThanContinuingFromTheFirst() throws {
        let day1 = date(0, 0)
        let day2 = date(1, 0)
        let stops = [
            stop(.start),
            stop(.pickup, day: day1, windowStart: date(0, 9), serviceDurationMinutes: 30, travelTime: 3600),
            stop(.dropoff, day: day1, serviceDurationMinutes: 30, travelTime: 3600),
            // Even though day 1 ran until the evening, day 2 starts fresh at
            // 8am — plus the 30 min drive to this first stop.
            stop(.pickup, day: day2, travelTime: 1800),
        ]

        let scheduled = schedule(stops)

        let day1DropoffDeparture = try XCTUnwrap(scheduled[2].scheduledDeparture)
        XCTAssertTrue(calendar.isDate(day1DropoffDeparture, inSameDayAs: day1))

        let day2Arrival = try XCTUnwrap(scheduled[3].scheduledArrival)
        XCTAssertEqual(day2Arrival, date(1, RouteScheduler.defaultDayStartHour, 30))
    }

    /// A new day can't start before the truck has finished the previous
    /// day's work. Here day 1's drop-off doesn't open until the afternoon
    /// of day 2, so day 2's pickup has to wait for it. Resetting to 08:00
    /// regardless would put the truck in two places at once, and report a
    /// pickup it will actually miss as on time.
    func testANewDayStartsNoEarlierThanThePreviousDaysWorkFinished() throws {
        let day1 = date(0, 0)
        let day2 = date(1, 0)
        let stops = [
            stop(.start),
            // 08:00 + 1h drive = 09:00, 30 min on site → leaves 09:30.
            stop(.pickup, day: day1, serviceDurationMinutes: 30, travelTime: 3600),
            // Arrives 14:30 on day 1, but the drop-off doesn't open until
            // 14:00 on day 2; 30 min on site → leaves day 2 at 14:30.
            stop(
                .dropoff,
                day: day1,
                windowStart: date(1, 14),
                serviceDurationMinutes: 30,
                travelTime: 5 * 3600
            ),
            // Day 2's pickup closes at noon. 14:30 + 1h drive = 15:30: late.
            stop(.pickup, day: day2, deadline: date(1, 12), travelTime: 3600),
        ]

        let scheduled = schedule(stops)

        let arrivals = try scheduled.dropFirst().map { try XCTUnwrap($0.scheduledArrival) }
        XCTAssertEqual(arrivals, arrivals.sorted(), "every arrival must be no earlier than the one before it")

        XCTAssertEqual(try XCTUnwrap(scheduled[2].scheduledDeparture), date(1, 14, 30))
        XCTAssertEqual(try XCTUnwrap(scheduled[3].scheduledArrival), date(1, 15, 30))
        XCTAssertTrue(scheduled[3].isLate)
    }

    // MARK: Waiting for a window

    func testArrivingBeforeAWindowOpensWaitsRatherThanArrivingEarly() throws {
        let day = date(0, 0)
        let windowStart = date(0, 13)
        let stops = [
            stop(.start),
            // 8am day start + 1hr travel = 9am, well before the 1pm window.
            stop(.pickup, day: day, windowStart: windowStart, travelTime: 3600),
        ]

        let scheduled = schedule(stops)
        XCTAssertEqual(try XCTUnwrap(scheduled[1].scheduledArrival), windowStart)
    }

    // MARK: Service time propagation

    func testServiceDurationPushesBackEveryStopAfterIt() throws {
        let day = date(0, 0)
        let stops = [
            stop(.start),
            stop(.pickup, day: day, serviceDurationMinutes: 45, travelTime: 3600),
            stop(.dropoff, day: day, serviceDurationMinutes: 20, travelTime: 1800),
        ]

        let scheduled = schedule(stops)

        let pickupArrival = try XCTUnwrap(scheduled[1].scheduledArrival)
        let pickupDeparture = try XCTUnwrap(scheduled[1].scheduledDeparture)
        XCTAssertEqual(pickupDeparture, pickupArrival.addingTimeInterval(45 * 60))

        let dropoffArrival = try XCTUnwrap(scheduled[2].scheduledArrival)
        XCTAssertEqual(dropoffArrival, pickupDeparture.addingTimeInterval(1800))
    }

    // MARK: Late-deadline warnings

    func testArrivingAfterTheDeadlineIsMarkedLate() throws {
        let day = date(0, 0)
        let deadline = date(0, 8, 30)
        let stops = [
            stop(.start),
            // 8am day start + 1hr travel = 9am, after the 8:30 deadline.
            stop(.pickup, day: day, deadline: deadline, travelTime: 3600),
        ]

        let scheduled = schedule(stops)
        XCTAssertTrue(scheduled[1].isLate)
    }

    func testArrivingBeforeTheDeadlineIsNotLate() throws {
        let day = date(0, 0)
        let deadline = date(0, 17)
        let stops = [
            stop(.start),
            stop(.pickup, day: day, deadline: deadline, travelTime: 3600),
        ]

        let scheduled = schedule(stops)
        XCTAssertFalse(scheduled[1].isLate)
    }

    func testNoDeadlineIsNeverLate() {
        let day = date(0, 0)
        let stops = [
            stop(.start),
            stop(.pickup, day: day, travelTime: 999_999),
        ]

        let scheduled = schedule(stops)
        XCTAssertFalse(scheduled[1].isLate)
    }

    // MARK: Same-day work running past midnight

    /// A day's work that runs past midnight must keep moving forward. The
    /// operating day used to be derived from the clock's own calendar day,
    /// so the stop after midnight looked like a new day and snapped the
    /// clock back to 08:00 that morning — scheduling time travel.
    func testSameDayWorkPastMidnightKeepsMovingForward() throws {
        let day = date(0, 0)
        let stops = [
            stop(.start),
            // 08:00 + 10h drive = 18:00, then 2h on site → leaves 20:00.
            stop(.pickup, day: day, serviceDurationMinutes: 120, travelTime: 10 * 3600),
            // + 6h drive = 02:00 the next calendar morning, then 1h on site
            // → leaves 03:00. Still this operating day's work.
            stop(.dropoff, day: day, serviceDurationMinutes: 60, travelTime: 6 * 3600),
            // This is the stop that used to break: the clock is already past
            // midnight, so deriving the operating day from it saw a new day
            // and snapped back to 08:00 that morning.
            stop(.pickup, day: day, travelTime: 3600),
            stop(.end, travelTime: 3600),
        ]

        let scheduled = schedule(stops)

        let arrivals = try scheduled.dropFirst().map { try XCTUnwrap($0.scheduledArrival) }
        XCTAssertEqual(arrivals, arrivals.sorted(), "every arrival must be no earlier than the one before it")

        let dropoffDeparture = try XCTUnwrap(scheduled[2].scheduledDeparture)
        let afterMidnightArrival = try XCTUnwrap(scheduled[3].scheduledArrival)
        XCTAssertGreaterThan(afterMidnightArrival, dropoffDeparture)

        // The work genuinely lands on the following calendar day, which is
        // the case that used to reset the clock.
        XCTAssertFalse(calendar.isDate(afterMidnightArrival, inSameDayAs: day))
        XCTAssertEqual(try XCTUnwrap(scheduled[2].scheduledArrival), date(1, 2))
        XCTAssertEqual(afterMidnightArrival, date(1, 4))
        XCTAssertEqual(try XCTUnwrap(scheduled[4].scheduledArrival), date(1, 5))
    }

    func testAGenuinelyNewOperatingDayStillResetsAfterMidnightWork() throws {
        let day1 = date(0, 0)
        let day2 = date(1, 0)
        let stops = [
            stop(.start),
            // Runs to 02:00 on day 2's calendar date, but it's day 1's work.
            stop(.pickup, day: day1, serviceDurationMinutes: 0, travelTime: 18 * 3600),
            // Assigned to day 2, so this one does reset to day 2's start.
            stop(.pickup, day: day2, travelTime: 1800),
        ]

        let scheduled = schedule(stops)

        XCTAssertEqual(try XCTUnwrap(scheduled[1].scheduledArrival), date(1, 2))
        XCTAssertEqual(
            try XCTUnwrap(scheduled[2].scheduledArrival),
            date(1, RouteScheduler.defaultDayStartHour, 30)
        )
    }

    // MARK: Unmeasured legs

    /// A leg MapKit couldn't measure isn't zero drive time. The stop it leads
    /// to has no knowable arrival, and neither does anything after it that
    /// day — reporting the previous stop's departure as this one's arrival
    /// would show a stop as comfortably on time when nobody knows if it is.
    func testAMissingLegLeavesThatStopAndTheRestOfTheDayUnknown() {
        let day = date(0, 0)
        let stops = [
            stop(.start),
            stop(.pickup, day: day, serviceDurationMinutes: 30, travelTime: 3600),
            // MapKit never returned this leg.
            stop(.dropoff, day: day, serviceDurationMinutes: 30, travelTime: nil),
            stop(.end, travelTime: 3600),
        ]

        let scheduled = schedule(stops)

        // The measured stop before the gap is still scheduled normally.
        XCTAssertFalse(scheduled[1].hasUnknownSchedule)
        XCTAssertNotNil(scheduled[1].scheduledArrival)

        for index in [2, 3] {
            XCTAssertTrue(scheduled[index].hasUnknownSchedule, "stop \(index) should be unknown")
            XCTAssertNil(scheduled[index].scheduledArrival, "stop \(index) should have no arrival")
            XCTAssertNil(scheduled[index].scheduledDeparture, "stop \(index) should have no departure")
        }
    }

    func testAnUnknownArrivalIsNeverReportedAsOnTimeOrLate() {
        let day = date(0, 0)
        let stops = [
            stop(.start),
            stop(.pickup, day: day, travelTime: 3600),
            // Deadline long past, but with no drive time we can't claim it's
            // late any more than we can claim it's on time.
            stop(.dropoff, day: day, deadline: date(0, 9), travelTime: nil),
        ]

        let scheduled = schedule(stops)

        XCTAssertTrue(scheduled[2].hasUnknownSchedule)
        XCTAssertFalse(scheduled[2].isLate)
        XCTAssertNil(scheduled[2].scheduledArrival)
    }

    /// The next day's start time doesn't depend on how the previous day
    /// finished, so an unmeasured leg shouldn't poison it.
    func testANewOperatingDayRecoversFromAnEarlierMissingLeg() throws {
        let day1 = date(0, 0)
        let day2 = date(1, 0)
        let stops = [
            stop(.start),
            stop(.pickup, day: day1, travelTime: nil),
            stop(.pickup, day: day2, travelTime: 1800),
        ]

        let scheduled = schedule(stops)

        XCTAssertTrue(scheduled[1].hasUnknownSchedule)
        XCTAssertFalse(scheduled[2].hasUnknownSchedule)
        XCTAssertEqual(
            try XCTUnwrap(scheduled[2].scheduledArrival),
            date(1, RouteScheduler.defaultDayStartHour, 30)
        )
    }

    func testTheYardStartIsNotReportedAsAnUnknownSchedule() {
        let stops = [
            stop(.start),
            stop(.pickup, day: date(0, 0), travelTime: 3600),
        ]

        let scheduled = schedule(stops)

        // The start has no schedule because nothing has anchored the clock
        // yet, which is different from a schedule we failed to work out.
        XCTAssertFalse(scheduled[0].hasUnknownSchedule)
        XCTAssertNil(scheduled[0].scheduledArrival)
        XCTAssertFalse(scheduled[1].hasUnknownSchedule)
    }

    func testTheRouteCountsStopsItCouldNotSchedule() {
        let day = date(0, 0)
        let stops = [
            stop(.start),
            stop(.pickup, day: day, travelTime: 3600),
            stop(.dropoff, day: day, travelTime: nil),
            stop(.end, travelTime: 1800),
        ]

        let route = PlannedRoute(stops: schedule(stops))
        XCTAssertEqual(route.stopsWithUnknownSchedule, 2)
    }
}
