import CoreLocation
import XCTest
@testable import TruckRoute

final class PlannedRouteTests: XCTestCase {
    private let mile = DistanceUnit.miles.metersPerUnit

    /// A day that runs 10 empty miles to a pickup, 100 loaded to the drop-off,
    /// then 50 empty back to the yard.
    private func sampleRoute(rate: Double? = nil) -> PlannedRoute {
        var pickup = stop(.pickup, rate: rate)
        pickup.distance = 10 * mile

        var dropoff = stop(.dropoff, rate: rate)
        dropoff.distance = 100 * mile
        dropoff.allMiles = 110 * mile

        var home = stop(.end)
        home.distance = 50 * mile

        return PlannedRoute(stops: [stop(.start), pickup, dropoff, home])
    }

    private func stop(_ kind: StopKind, rate: Double? = nil) -> RouteStop {
        RouteStop(
            kind: kind,
            placeName: "Somewhere",
            address: "1 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            loadReference: nil,
            day: nil,
            loadRate: rate
        )
    }

    func testLoadedMilesCountOnlyLegsIntoADropOff() {
        XCTAssertEqual(sampleRoute().loadedDistance / mile, 100, accuracy: 0.001)
    }

    func testEmptyMilesIncludeTheRunToPickupAndTheRunHome() {
        XCTAssertEqual(sampleRoute().emptyDistance / mile, 60, accuracy: 0.001)
    }

    func testDeadheadShareIsEmptyMilesOverEveryMile() {
        XCTAssertEqual(try XCTUnwrap(sampleRoute().deadheadShare), 60.0 / 160.0, accuracy: 0.001)
    }

    func testRatePerMileIsMeasuredOverEmptyMilesToo() throws {
        // $1,000 over 160 miles driven, not the 100 loaded ones.
        let route = sampleRoute(rate: 1000)
        XCTAssertEqual(try XCTUnwrap(route.rate(per: .miles)), 6.25, accuracy: 0.001)
    }

    func testRatePerKilometerIsTheSameMoneyOverMoreUnits() throws {
        let route = sampleRoute(rate: 1000)
        let perKm = try XCTUnwrap(route.rate(per: .kilometers))
        XCTAssertEqual(perKm, 1000.0 / (160 * mile / 1000), accuracy: 0.001)
        // A rate per km is necessarily the smaller number.
        XCTAssertLessThan(perKm, try XCTUnwrap(route.rate(per: .miles)))
    }

    func testLoadRatePerMileIncludesItsOwnDeadhead() throws {
        let dropoff = try XCTUnwrap(sampleRoute(rate: 1000).stops.first { $0.kind == .dropoff })
        XCTAssertEqual(try XCTUnwrap(dropoff.rate(per: .miles)), 1000.0 / 110.0, accuracy: 0.001)
    }

    // MARK: Per-load miles

    func testALoadsMilesAreItsEmptyRunInPlusItsLoadedRun() throws {
        var route = sampleRoute(rate: 1000)
        route.stops[2].allMiles = nil
        route.assignLoadMiles()
        XCTAssertEqual(try XCTUnwrap(route.stops[2].allMiles) / mile, 110, accuracy: 0.001)
    }

    /// Counting a leg MapKit couldn't measure as zero miles made the load
    /// look better than it is: here it would have been $1,000 over the 10
    /// empty miles alone, $100/mi.
    func testALoadWithAnUnmeasuredLoadedLegHasNoRatePerMile() {
        var route = sampleRoute(rate: 1000)
        route.stops[2].distance = nil
        route.assignLoadMiles()
        XCTAssertNil(route.stops[2].allMiles)
        XCTAssertNil(route.stops[2].rate(per: .miles))
    }

    func testALoadWithAnUnmeasuredEmptyLegHasNoRatePerMile() {
        var route = sampleRoute(rate: 1000)
        route.stops[1].distance = nil
        route.assignLoadMiles()
        XCTAssertNil(route.stops[2].allMiles)
        XCTAssertNil(route.stops[2].rate(per: .miles))
    }

    func testTotalRateCountsEachLoadOnceRatherThanPerStop() throws {
        // The rate rides on both the pickup and the drop-off stop.
        XCTAssertEqual(try XCTUnwrap(sampleRoute(rate: 1000).totalRate), 1000, accuracy: 0.001)
    }

    func testRateIsNilWhenNoLoadHasOne() {
        XCTAssertNil(sampleRoute().totalRate)
        XCTAssertNil(sampleRoute().rate(per: .miles))
    }

    func testWorkingStopCountExcludesTheYardAtBothEnds() {
        XCTAssertEqual(sampleRoute().workingStopCount, 2)
    }

    func testUnmeasuredLegsAreCountedSoTotalsCanBeFlaggedAsLow() {
        var route = sampleRoute()
        route.stops[2].distance = nil
        XCTAssertEqual(route.unmeasuredLegs, 1)
    }

    func testEmptyRouteReportsNothingRatherThanDividingByZero() {
        let empty = PlannedRoute()
        XCTAssertEqual(empty.totalDistance, 0)
        XCTAssertNil(empty.deadheadShare)
        XCTAssertNil(empty.rate(per: .miles))
        XCTAssertEqual(empty.workingStopCount, 0)
    }
}
