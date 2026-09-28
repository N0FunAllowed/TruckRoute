import Foundation
import CoreLocation
import MapKit

enum StopKind {
    case start
    case pickup
    case dropoff
    case end

    var label: String {
        switch self {
        case .start: "Start"
        case .pickup: "Pick up"
        case .dropoff: "Drop off"
        case .end: "Back to yard"
        }
    }
}

struct RouteStop: Identifiable {
    let id = UUID()
    let kind: StopKind
    let placeName: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let loadReference: String?
    let day: Date?
    /// What the load this stop belongs to pays. Nil on the start.
    let loadRate: Double?

    /// The earliest this stop can be worked — arriving before this means
    /// waiting. Nil means no window, so any arrival time is fine.
    let windowStart: Date?
    /// The latest this stop should be worked. Nil means no deadline. For a
    /// drop-off this is the delivery window's end if one was set, otherwise
    /// the load's plain delivery deadline — see `Load.deliveryWindowEnd`.
    let deadline: Date?
    /// How long the truck sits here before it can leave. Zero for the yard
    /// stops at either end of the route.
    let serviceDurationMinutes: Int

    init(
        kind: StopKind,
        placeName: String,
        address: String,
        coordinate: CLLocationCoordinate2D,
        loadReference: String?,
        day: Date?,
        loadRate: Double?,
        windowStart: Date? = nil,
        deadline: Date? = nil,
        serviceDurationMinutes: Int = 0
    ) {
        self.kind = kind
        self.placeName = placeName
        self.address = address
        self.coordinate = coordinate
        self.loadReference = loadReference
        self.day = day
        self.loadRate = loadRate
        self.windowStart = windowStart
        self.deadline = deadline
        self.serviceDurationMinutes = serviceDurationMinutes
    }

    /// Drive from the previous stop to this one. Nil for the start, or if
    /// MapKit couldn't find a road route.
    var travelTime: TimeInterval?
    var distance: CLLocationDistance?
    var polyline: MKPolyline?

    /// When the truck is scheduled to reach this stop and to leave it again,
    /// filled in by `RouteScheduler` once legs are measured. Nil until then,
    /// and nil when `hasUnknownSchedule` is true.
    var scheduledArrival: Date?
    var scheduledDeparture: Date?
    /// True when the scheduled arrival is after `deadline`. Always false when
    /// the schedule is unknown — an arrival nobody can work out isn't late,
    /// and it certainly isn't on time.
    var isLate: Bool = false
    /// True when the drive to this stop, or to something before it that day,
    /// was never measured, so there's no honest arrival time to give. Distinct
    /// from the yard start, which simply has no schedule to report.
    var hasUnknownSchedule: Bool = false

    /// Every leg driven to earn this load: the empty run to its pickup plus
    /// the loaded run to its drop-off. Set on drop-off stops once legs are
    /// measured, and left nil if either leg couldn't be — see
    /// `PlannedRoute.assignLoadMiles()`.
    var allMiles: CLLocationDistance?

    /// The leg arriving here is empty — running to a pickup with nothing on,
    /// or heading home after the last drop. Empty miles earn nothing, so
    /// they're what separates a good rate from a bad one.
    var isDeadheadLeg: Bool { kind == .pickup || kind == .end }

    /// Rate per unit measured against every mile driven for this load, loaded
    /// and empty, which is how owner-operators judge one.
    func rate(per unit: DistanceUnit) -> Double? {
        guard let loadRate, let allMiles, allMiles > 0 else { return nil }
        return loadRate / (allMiles / unit.metersPerUnit)
    }
}

/// A load left out of the route, because it has no pickup or drop-off set or
/// because an address wouldn't geocode.
struct SkippedLoad: Identifiable {
    let id = UUID()
    let reference: String
    let reason: String
}

struct PlannedRoute {
    var stops: [RouteStop] = []
    var skipped: [SkippedLoad] = []

    /// Pickups and drop-offs, not the yard at either end.
    var workingStopCount: Int {
        stops.filter { $0.kind == .pickup || $0.kind == .dropoff }.count
    }

    var totalDistance: CLLocationDistance {
        stops.compactMap(\.distance).reduce(0, +)
    }

    var totalTravelTime: TimeInterval {
        stops.compactMap(\.travelTime).reduce(0, +)
    }

    var loadedDistance: CLLocationDistance {
        stops.filter { !$0.isDeadheadLeg }.compactMap(\.distance).reduce(0, +)
    }

    var emptyDistance: CLLocationDistance {
        stops.filter(\.isDeadheadLeg).compactMap(\.distance).reduce(0, +)
    }

    /// Legs MapKit couldn't measure. Any of these means the mileage and the
    /// rate per mile below are understated, so the route says so rather than
    /// quietly reporting a number that's too good.
    var unmeasuredLegs: Int {
        stops.dropFirst().filter { $0.distance == nil }.count
    }

    /// Stops whose arrival can't be worked out because a drive time is
    /// missing. Separate from `unmeasuredLegs`, which counts the mileage
    /// those same gaps cost: one unmeasured leg can leave several later
    /// stops unschedulable.
    var stopsWithUnknownSchedule: Int {
        stops.filter(\.hasUnknownSchedule).count
    }

    var deadheadShare: Double? {
        guard totalDistance > 0 else { return nil }
        return emptyDistance / totalDistance
    }

    /// Nil when no load on the route has a rate entered.
    var totalRate: Double? {
        let rates = stops.filter { $0.kind == .dropoff }.compactMap(\.loadRate)
        return rates.isEmpty ? nil : rates.reduce(0, +)
    }

    /// Revenue over every mile of the route, empty ones included.
    func rate(per unit: DistanceUnit) -> Double? {
        guard let totalRate, totalDistance > 0 else { return nil }
        return totalRate / (totalDistance / unit.metersPerUnit)
    }

    /// Fills in `allMiles` on every drop-off from the legs already measured.
    ///
    /// A load's miles are the empty run to its pickup plus the loaded run to
    /// its drop-off. Stops are built pickup-then-drop-off, so the leg before
    /// a drop-off is always that load's deadhead. If either leg couldn't be
    /// measured the load's miles are unknown, not short: counting the gap as
    /// zero would report a rate per mile better than the real one, on the
    /// one number that decides whether a load was worth taking.
    mutating func assignLoadMiles() {
        for index in stops.indices where stops[index].kind == .dropoff {
            guard index > 0,
                  let loaded = stops[index].distance,
                  let empty = stops[index - 1].distance
            else {
                stops[index].allMiles = nil
                continue
            }
            stops[index].allMiles = loaded + empty
        }
    }
}
