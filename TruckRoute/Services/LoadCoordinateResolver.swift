import Foundation
import CoreLocation

/// Resolves the coordinate to route a load's pickup or drop-off through.
///
/// A load never caches its own coordinate — it only holds a reference to a
/// `Place`, and a `Place` caches its own geocoded coordinate. That means
/// editing a place's address (which clears its cached coordinate — see
/// `PlaceFormView.save`) automatically un-stales every load that points at
/// it: there's nothing stored on the load itself that could go stale. This
/// resolver is the single place that reads through to a place's *current*
/// address and coordinate, so nothing else in the app can quietly take a
/// shortcut back to an old one.
///
/// The geocoder is injected so this is testable without a network call or a
/// live `CLGeocoder`/MapKit round trip.
///
/// The resolving methods are `@MainActor` because they read and write a
/// `Place` that belongs to the main model context. A plain `async` method
/// doesn't inherit its caller's actor, so even called from the main-actor
/// `RoutePlanner` it would run on a background executor and touch SwiftData
/// off the main thread.
struct LoadCoordinateResolver {
    typealias Geocoder = (String) async throws -> CLLocationCoordinate2D

    let geocoder: Geocoder

    static let live = LoadCoordinateResolver { address in
        try await GeocodingService.shared.coordinate(for: address)
    }

    /// The place's coordinate if it already has one cached; otherwise geocodes
    /// its current address and caches the result back onto the place, so the
    /// next call (this load or any other pointing at the same place) is free.
    @MainActor
    func resolve(_ place: Place) async throws -> CLLocationCoordinate2D {
        if let cached = place.coordinate {
            return cached
        }
        let coordinate = try await geocoder(place.address)
        place.coordinate = coordinate
        return coordinate
    }

    @MainActor
    func resolvePickup(of load: Load) async throws -> CLLocationCoordinate2D {
        guard let pickup = load.pickup else {
            throw LoadCoordinateError.missingPlace(role: "pickup")
        }
        return try await resolve(pickup)
    }

    @MainActor
    func resolveDropoff(of load: Load) async throws -> CLLocationCoordinate2D {
        guard let dropoff = load.dropoff else {
            throw LoadCoordinateError.missingPlace(role: "drop-off")
        }
        return try await resolve(dropoff)
    }
}

enum LoadCoordinateError: LocalizedError {
    case missingPlace(role: String)

    var errorDescription: String? {
        switch self {
        case .missingPlace(let role): "No \(role) address set."
        }
    }
}
