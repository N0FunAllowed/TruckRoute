import Foundation
import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class RoutePlanner {
    private(set) var route: PlannedRoute?
    private(set) var isPlanning = false
    private(set) var progressNote: String?
    private(set) var errorMessage: String?

    /// Fingerprint of the loads and yard the current route was built from, so
    /// the Route tab can tell when what's on screen no longer matches the
    /// board. Nil when nothing has been planned yet.
    private(set) var plannedSignature: Int?

    private let coordinateResolver: LoadCoordinateResolver

    /// When the last directions request was sent, so the next one can wait out
    /// the remainder of `directionsInterval` rather than piling on. Pacing is
    /// bookkeeping, not state any view should re-render for.
    @ObservationIgnored private var lastDirectionsRequest: ContinuousClock.Instant?

    init(coordinateResolver: LoadCoordinateResolver = .live) {
        self.coordinateResolver = coordinateResolver
    }

    /// Orders the week's loads and measures each leg.
    ///
    /// Loads are grouped by pickup day so the truck never runs a Friday load on
    /// Monday. `RouteOrdering` then decides the order within each day — see
    /// there for the two rules it applies.
    func plan(loads: [Load], from homeBase: Place) async {
        guard !isPlanning else { return }
        isPlanning = true
        errorMessage = nil
        defer {
            isPlanning = false
            progressNote = nil
        }

        plannedSignature = Self.signature(loads: loads, homeBase: homeBase)

        guard !loads.isEmpty else {
            route = PlannedRoute()
            return
        }

        progressNote = "Looking up addresses…"
        let start: CLLocationCoordinate2D
        do {
            start = try await coordinateResolver.resolve(homeBase)
        } catch {
            errorMessage = "Couldn't find the address for \(homeBase.displayName), your home base."
            return
        }

        var routable: [(load: Load, pickup: CLLocationCoordinate2D, dropoff: CLLocationCoordinate2D)] = []
        var skipped: [SkippedLoad] = []

        for load in loads {
            guard let pickup = load.pickup, let dropoff = load.dropoff else {
                skipped.append(SkippedLoad(
                    reference: load.displayName,
                    reason: "No pickup or drop-off set."
                ))
                continue
            }
            do {
                routable.append((
                    load,
                    try await coordinateResolver.resolve(pickup),
                    try await coordinateResolver.resolve(dropoff)
                ))
            } catch {
                skipped.append(SkippedLoad(
                    reference: load.displayName,
                    reason: error.localizedDescription
                ))
            }
        }

        var stops = [RouteStop(
            kind: .start,
            placeName: homeBase.displayName,
            address: homeBase.address,
            coordinate: start,
            loadReference: nil,
            day: nil,
            loadRate: nil
        )]

        let calendar = Calendar.current
        let byDay = Dictionary(grouping: routable) {
            calendar.startOfDay(for: $0.load.pickupDate)
        }

        var current = start
        for day in byDay.keys.sorted() {
            let dayLoads = byDay[day] ?? []
            let ordered = RouteOrdering.order(
                dayLoads.map {
                    OrderableLoad(
                        pickupOpens: $0.load.pickupDate,
                        pickup: $0.pickup,
                        dropoff: $0.dropoff
                    )
                },
                from: current,
                calendar: calendar
            )

            for index in ordered {
                let entry = dayLoads[index]
                stops.append(RouteStop(
                    kind: .pickup,
                    placeName: entry.load.pickup?.displayName ?? "",
                    address: entry.load.pickup?.address ?? "",
                    coordinate: entry.pickup,
                    loadReference: entry.load.displayName,
                    day: day,
                    loadRate: entry.load.rate,
                    windowStart: entry.load.pickupDate,
                    deadline: entry.load.pickupWindowEnd,
                    serviceDurationMinutes: entry.load.serviceDurationMinutes
                ))
                stops.append(RouteStop(
                    kind: .dropoff,
                    placeName: entry.load.dropoff?.displayName ?? "",
                    address: entry.load.dropoff?.address ?? "",
                    coordinate: entry.dropoff,
                    loadReference: entry.load.displayName,
                    day: day,
                    loadRate: entry.load.rate,
                    windowStart: entry.load.deliveryWindowStart,
                    deadline: entry.load.deliveryWindowEnd ?? entry.load.deliveryDate,
                    serviceDurationMinutes: entry.load.serviceDurationMinutes
                ))
                current = entry.dropoff
            }
        }

        // The empty run home is real deadhead, so the day isn't costed
        // honestly without it.
        if stops.count > 1 {
            stops.append(RouteStop(
                kind: .end,
                placeName: homeBase.displayName,
                address: homeBase.address,
                coordinate: start,
                loadReference: nil,
                day: nil,
                loadRate: nil
            ))
        }

        route = PlannedRoute(stops: stops, skipped: skipped)
        await measureLegs()
    }

    func clear() {
        route = nil
        plannedSignature = nil
        errorMessage = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    /// A fingerprint of everything a plan depends on.
    ///
    /// Compared against `plannedSignature` to spot a route that's gone stale:
    /// editing a load's times, swapping an address, marking one delivered or
    /// adding a new one all leave the old plan on screen looking authoritative
    /// when it no longer describes the week.
    ///
    /// Per-load hashes are sorted before being combined so the result doesn't
    /// depend on the order the query happened to return. It's only ever
    /// compared with another value from the same process, which is all
    /// `Hasher` guarantees.
    static func signature(loads: [Load], homeBase: Place) -> Int {
        var perLoad: [Int] = []
        for load in loads {
            var hasher = Hasher()
            hasher.combine(load.persistentModelID)
            hasher.combine(load.pickup?.persistentModelID)
            hasher.combine(load.dropoff?.persistentModelID)
            hasher.combine(load.pickup?.address)
            hasher.combine(load.dropoff?.address)
            hasher.combine(load.pickupDate)
            hasher.combine(load.pickupWindowEnd)
            hasher.combine(load.deliveryDate)
            hasher.combine(load.deliveryWindowStart)
            hasher.combine(load.deliveryWindowEnd)
            hasher.combine(load.serviceDurationMinutes)
            hasher.combine(load.rate)
            hasher.combine(load.isDelivered)
            perLoad.append(hasher.finalize())
        }

        var hasher = Hasher()
        hasher.combine(homeBase.persistentModelID)
        hasher.combine(homeBase.address)
        for value in perLoad.sorted() {
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    /// Fills in drive time, distance and the drawable polyline for each leg.
    /// A leg that MapKit can't route (islands, bad address, throttling) stays
    /// nil rather than falling back to a straight line that would understate
    /// the real drive.
    private func measureLegs() async {
        guard var working = route else { return }

        for index in working.stops.indices.dropFirst() {
            progressNote = "Measuring leg \(index) of \(working.stops.count - 1)…"

            if let leg = await drivingRoute(
                from: working.stops[index - 1].coordinate,
                to: working.stops[index].coordinate
            ) {
                working.stops[index].travelTime = leg.expectedTravelTime
                working.stops[index].distance = leg.distance
                working.stops[index].polyline = leg.polyline
            }
            route = working
        }

        working.assignLoadMiles()
        working.stops = RouteScheduler.schedule(working.stops)
        route = working
    }

    /// MapKit throttles directions requests and starts refusing them once they
    /// come back to back. A refused leg isn't an error the user sees — it just
    /// goes unmeasured, understating the miles, the rate per mile and the
    /// schedule. A 25-load week is 51 legs, so firing them off as fast as they
    /// complete runs straight into that limit.
    ///
    /// Apple doesn't publish the ceiling; roughly 50 requests a minute is the
    /// figure that holds up in practice, so requests are spaced to stay under
    /// it. This is the slow part of planning, which is why `plan` reports
    /// progress per leg.
    private static let directionsInterval: Duration = .milliseconds(1_250)

    private func drivingRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> MKRoute? {
        // Two attempts: one paced normally, and if that was refused anyway, one
        // after a longer wait. Backing off further would cost more than the leg
        // is worth — it's reported as unmeasured instead.
        for attempt in 0..<2 {
            await pace(extra: attempt > 0 ? .seconds(3) : .zero)

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = .automobile

            if let leg = try? await MKDirections(request: request).calculate().routes.first {
                return leg
            }
        }
        return nil
    }

    /// Sleeps until at least `directionsInterval` (plus `extra`) has passed
    /// since the last directions request, then marks this moment as the latest.
    private func pace(extra: Duration) async {
        let gap = Self.directionsInterval + extra
        if let last = lastDirectionsRequest {
            let waited = ContinuousClock.now - last
            if waited < gap {
                try? await Task.sleep(for: gap - waited)
            }
        }
        lastDirectionsRequest = ContinuousClock.now
    }
}
