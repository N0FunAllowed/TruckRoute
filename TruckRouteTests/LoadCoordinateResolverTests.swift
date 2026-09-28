import CoreLocation
import XCTest
@testable import TruckRoute

final class LoadCoordinateResolverTests: XCTestCase {
    private let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    private let oakland = CLLocationCoordinate2D(latitude: 37.8044, longitude: -122.2712)

    /// A geocoder stub that records every address it was asked to look up and
    /// returns a coordinate keyed to that address, so a test can prove which
    /// address the resolver actually used.
    private final class RecordingGeocoder {
        private(set) var lookups: [String] = []
        var coordinates: [String: CLLocationCoordinate2D] = [:]

        func geocode(_ address: String) async throws -> CLLocationCoordinate2D {
            lookups.append(address)
            guard let coordinate = coordinates[address] else {
                throw LoadCoordinateError.missingPlace(role: address)
            }
            return coordinate
        }
    }

    func testAPlaceWithACachedCoordinateNeverGeocodes() async throws {
        let geocoder = RecordingGeocoder()
        let resolver = LoadCoordinateResolver(geocoder: geocoder.geocode)
        let place = Place(name: "Yard", address: "1 Dock Rd")
        place.coordinate = sanFrancisco

        let resolved = try await resolver.resolve(place)

        XCTAssertEqual(resolved.latitude, sanFrancisco.latitude, accuracy: 0.0001)
        XCTAssertTrue(geocoder.lookups.isEmpty)
    }

    func testAPlaceWithNoCoordinateGeocodesItsCurrentAddressAndCachesTheResult() async throws {
        let geocoder = RecordingGeocoder()
        geocoder.coordinates["1 Dock Rd"] = sanFrancisco
        let resolver = LoadCoordinateResolver(geocoder: geocoder.geocode)
        let place = Place(name: "Yard", address: "1 Dock Rd")

        let resolved = try await resolver.resolve(place)

        XCTAssertEqual(resolved.latitude, sanFrancisco.latitude, accuracy: 0.0001)
        XCTAssertEqual(geocoder.lookups, ["1 Dock Rd"])
        let cached = try XCTUnwrap(place.coordinate)
        XCTAssertEqual(cached.latitude, sanFrancisco.latitude, accuracy: 0.0001)
    }

    /// Editing a place clears its cached coordinate (see `PlaceFormView.save`)
    /// but the load keeps pointing at the same `Place` object — it never held
    /// a coordinate of its own. Resolving after that edit must pick up the
    /// new address rather than any value seen before.
    func testEditingAPlacesAddressMakesTheNextResolveUseTheNewAddress() async throws {
        let geocoder = RecordingGeocoder()
        geocoder.coordinates["1 Old Dock Rd"] = sanFrancisco
        geocoder.coordinates["2 New Dock Rd"] = oakland
        let resolver = LoadCoordinateResolver(geocoder: geocoder.geocode)
        let place = Place(name: "Yard", address: "1 Old Dock Rd")

        _ = try await resolver.resolve(place)
        let cachedBeforeEdit = try XCTUnwrap(place.coordinate)
        XCTAssertEqual(cachedBeforeEdit.latitude, sanFrancisco.latitude, accuracy: 0.0001)

        // Simulate PlaceFormView.save(): address changes, cached coordinate clears.
        place.address = "2 New Dock Rd"
        place.coordinate = nil

        let resolvedAfterEdit = try await resolver.resolve(place)

        XCTAssertEqual(resolvedAfterEdit.latitude, oakland.latitude, accuracy: 0.0001)
        XCTAssertEqual(geocoder.lookups, ["1 Old Dock Rd", "2 New Dock Rd"])
    }

    /// Two loads sharing one place both see the same, current coordinate —
    /// there's no per-load cache that could disagree with the place.
    func testTwoLoadsSharingAPlaceSeeTheSameCoordinateAfterAnEdit() async throws {
        let geocoder = RecordingGeocoder()
        geocoder.coordinates["1 Old Dock Rd"] = sanFrancisco
        geocoder.coordinates["2 New Dock Rd"] = oakland
        let resolver = LoadCoordinateResolver(geocoder: geocoder.geocode)

        let place = Place(name: "Yard", address: "1 Old Dock Rd")
        let firstLoad = Load(pickup: place)
        let secondLoad = Load(pickup: place)

        _ = try await resolver.resolvePickup(of: firstLoad)

        place.address = "2 New Dock Rd"
        place.coordinate = nil

        let firstAfterEdit = try await resolver.resolvePickup(of: firstLoad)
        let secondAfterEdit = try await resolver.resolvePickup(of: secondLoad)

        XCTAssertEqual(firstAfterEdit.latitude, oakland.latitude, accuracy: 0.0001)
        XCTAssertEqual(secondAfterEdit.latitude, oakland.latitude, accuracy: 0.0001)
        // The second load's resolve found the coordinate already cached from
        // the first, so the address was only looked up once after the edit.
        XCTAssertEqual(geocoder.lookups, ["1 Old Dock Rd", "2 New Dock Rd"])
    }

    func testResolvingAPickupWithNoPlaceSetThrows() async {
        let resolver = LoadCoordinateResolver { _ in self.sanFrancisco }
        let load = Load()

        do {
            _ = try await resolver.resolvePickup(of: load)
            XCTFail("Expected resolvePickup to throw when no pickup place is set")
        } catch {
            // Expected.
        }
    }

    func testResolvingADropoffWithNoPlaceSetThrows() async {
        let resolver = LoadCoordinateResolver { _ in self.sanFrancisco }
        let load = Load()

        do {
            _ = try await resolver.resolveDropoff(of: load)
            XCTFail("Expected resolveDropoff to throw when no drop-off place is set")
        } catch {
            // Expected.
        }
    }
}
