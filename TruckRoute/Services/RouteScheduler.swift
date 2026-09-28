import Foundation

/// Walks a planned route's stops in order and works out when the truck is
/// scheduled to reach and leave each one.
///
/// This is a pure, synchronous function over `[RouteStop]` — it needs
/// nothing from MapKit or the network, only each stop's already-measured
/// `travelTime`. That's deliberate: it's the one piece of the route planner
/// worth unit-testing directly, without standing up a live directions call
/// for every scenario.
enum RouteScheduler {
    /// When a working day starts if nothing says otherwise.
    static let defaultDayStartHour = 8

    /// Returns the same stops with `scheduledArrival`, `scheduledDeparture`,
    /// `isLate` and `hasUnknownSchedule` filled in.
    ///
    /// The clock only ever anchors from a stop's own `day` — never from the
    /// yard stops at either end, which carry no day of their own. That's what
    /// keeps a route whose first load is days out from being scheduled as if
    /// it started this morning: nothing anchors the clock until the first
    /// stop that actually has a day does.
    static func schedule(
        _ stops: [RouteStop],
        calendar: Calendar = .current
    ) -> [RouteStop] {
        var result = stops
        var clock: Date?
        /// The operating day the clock is currently working through. Tracked
        /// separately from the clock itself on purpose: a day's work can run
        /// past midnight, and deriving the operating day from the clock's own
        /// calendar day would then see the next same-day stop as a new day
        /// and reset the clock backwards to that morning.
        var activeOperatingDay: Date?
        /// Set once a leg's drive time is missing. Everything downstream of
        /// that within the same operating day is a guess, so it's reported as
        /// unknown rather than as an optimistic time.
        var scheduleIsUnknown = false

        for index in result.indices {
            var stop = result[index]
            let stopDay = stop.day.map { calendar.startOfDay(for: $0) }

            // Reset only when the stop's *assigned* operating day advances.
            if let stopDay, stopDay != activeOperatingDay {
                activeOperatingDay = stopDay
                // A new day starts at its usual hour unless the truck is
                // still busy with the previous day's work by then — a drop
                // whose window opens the next afternoon, say. The truck can't
                // be in two places, so the later of the two wins; always
                // taking the day start would schedule the new day's first
                // stop before the truck could possibly get there and hide it
                // being late.
                let start = dayStart(for: stopDay, calendar: calendar)
                clock = max(start, clock ?? start)
                // An earlier unmeasured leg left the clock nil, so this day
                // is anchored to its own start and the unknown stops
                // mattering from here. That assumes the unknown day finished
                // before this one began, which is the open design question
                // `testANewOperatingDayRecoversFromAnEarlierMissingLeg` pins.
                scheduleIsUnknown = false
            }

            // Resetting the clock for a new day is not a substitute for the
            // drive to get here: the two were once an if/else, which made the
            // first stop of any day look like it arrived with no travel at all.
            if index > 0 {
                if let travelTime = stop.travelTime {
                    clock = clock?.addingTimeInterval(travelTime)
                } else {
                    scheduleIsUnknown = true
                }
            }

            guard !scheduleIsUnknown else {
                stop.hasUnknownSchedule = true
                stop.scheduledArrival = nil
                stop.scheduledDeparture = nil
                // An unknown arrival can't be called late — or on time.
                stop.isLate = false
                clock = nil
                result[index] = stop
                continue
            }

            // Arriving before the window opens just means waiting for it.
            if let windowStart = stop.windowStart, let arrival = clock, arrival < windowStart {
                clock = windowStart
            }

            stop.hasUnknownSchedule = false
            stop.scheduledArrival = clock

            if let deadline = stop.deadline, let arrival = clock {
                stop.isLate = arrival > deadline
            } else {
                stop.isLate = false
            }

            let departure = clock?.addingTimeInterval(TimeInterval(stop.serviceDurationMinutes * 60))
            stop.scheduledDeparture = departure
            clock = departure

            result[index] = stop
        }

        return result
    }

    private static func dayStart(for day: Date, calendar: Calendar) -> Date {
        calendar.date(
            bySettingHour: defaultDayStartHour,
            minute: 0,
            second: 0,
            of: day
        ) ?? day
    }
}
