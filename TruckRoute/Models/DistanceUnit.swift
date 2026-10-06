import Foundation
import CoreLocation

/// Which unit distances and rates are shown in. Rate per mile and rate per
/// kilometre are different numbers, so this drives both the distances and the
/// label on every rate.
enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles
    case kilometers

    static let storageKey = "distanceUnit"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .miles: "Miles"
        case .kilometers: "Kilometers"
        }
    }

    var abbreviation: String {
        switch self {
        case .miles: "mi"
        case .kilometers: "km"
        }
    }

    var metersPerUnit: CLLocationDistance {
        switch self {
        case .miles: 1609.344
        case .kilometers: 1000
        }
    }

    var unitLength: UnitLength {
        switch self {
        case .miles: .miles
        case .kilometers: .kilometers
        }
    }
}
