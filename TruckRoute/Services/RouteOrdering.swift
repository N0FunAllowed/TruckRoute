import Foundation
import CoreLocation

/// One load reduced to just what deciding its place in the day needs.
struct OrderableLoad {
    let pickupOpens: Date
    let pickup: CLLocationCoordinate2D
    let dropoff: CLLocationCoordinate2D

    init(pickupOpens: Date, pickup: CLLocationCoordinate2D, dropoff: CLLocationCoordinate2D) {
        self.pickupOpens = pickupOpens
        self.pickup = pickup
        self.dropoff = dropoff
    }
}

/// Decides what order one day's loads get worked in.
///
/// Pure and synchronous, like `RouteScheduler`: it takes coordinates that are
/// already resolved and never touches MapKit or the network, so every ordering
/// rule below can be tested directly.
enum RouteOrdering {
    /// Loads whose pickups open within the same hour are treated as opening at
    /// the same time. Entering a week of loads without thinking about the clock
    /// leaves each one stamped with whatever minute it was typed, and ordering
    /// strictly by that would shuffle the day for no reason.
    static let openingGranularity: Calendar.Component = .hour

    /// Returns the indices of `loads` in the order they should be worked.
    ///
    /// Two rules, in this order:
    ///
    /// 1. **A pickup that opens earlier is worked first.** Nearest-neighbor on
    ///    its own will happily take a 14:00 pickup near the yard before an
    ///    08:00 pickup an hour away, idle six hours, then run the 08:00 load
    ///    that evening — past a window close it had no way to see.
    /// 2. **Among pickups opening in the same hour, the nearest wins.** This is
    ///    the old behaviour, and it still decides the whole day whenever the
    ///    loads carry no real time intent, which is the common case.
    ///
    /// Distance is straight-line from wherever the truck sits after the last
    /// drop-off. That's good enough to pick the next stop and avoids a
    /// directions request per candidate.
    static func order(
        _ loads: [OrderableLoad],
        from start: CLLocationCoordinate2D,
        calendar: Calendar = .current
    ) -> [Int] {
        var remaining = Array(loads.indices)
        var order: [Int] = []
        var current = start

        while !remaining.isEmpty {
            // The earliest opening still outstanding sets the wave; anything
            // opening in that same hour competes on distance alone.
            let earliest = remaining
                .map { openingSlot(of: loads[$0], calendar: calendar) }
                .min()!

            let wave = remaining.filter {
                openingSlot(of: loads[$0], calendar: calendar) == earliest
            }

            let next = wave.min {
                straightLineDistance(from: current, to: loads[$0].pickup)
                    < straightLineDistance(from: current, to: loads[$1].pickup)
            }!

            order.append(next)
            remaining.removeAll { $0 == next }
            current = loads[next].dropoff
        }

        return order
    }

    /// The start of the hour a pickup opens in — see `openingGranularity`.
    private static func openingSlot(of load: OrderableLoad, calendar: Calendar) -> Date {
        calendar.dateInterval(of: openingGranularity, for: load.pickupOpens)?.start
            ?? load.pickupOpens
    }

    private static func straightLineDistance(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
