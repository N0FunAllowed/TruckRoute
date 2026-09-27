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

    private let coordinateResolver: LoadCoordinateResolver

    init(coordinateResolver: LoadCoordinateResolver = .live) {
        self.coordinateResolver = coordinateResolver
    }

    /// Orders the week's loads and measures each leg.
    ///
    /// Loads are grouped by pickup day so the truck never runs a Friday load on
    /// Monday, then ordered within each day by nearest-neighbor: from where the
    /// truck currently sits, take the closest remaining pickup, run it to its
    /// drop-off, repeat. Distance for ordering is straight-line — good enough to
    /// pick the next stop, and it avoids a directions request per candidate.
    func plan(loads: [Load], from homeBase: Place) async {
        guard !isPlanning else { return }
        isPlanning = true
        errorMessage = nil
        defer {
            isPlanning = false
            progressNote = nil
        }

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
            var remaining = byDay[day] ?? []
            while !remaining.isEmpty {
                let index = remaining.indices.min { a, b in
                    distance(from: current, to: remaining[a].pickup)
                        < distance(from: current, to: remaining[b].pickup)
                }!
                let entry = remaining.remove(at: index)
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
        errorMessage = nil
    }

    func dismissError() {
        errorMessage = nil
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

    /// MapKit throttles directions requests and starts refusing them when they
    /// come back to back, which would silently drop legs and understate both
    /// the miles and the rate per mile. Space them out, and give a refused
    /// request one more try before giving up on the leg.
    private func drivingRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> MKRoute? {
        for attempt in 0..<2 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(1))
            }
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

    private func distance(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
