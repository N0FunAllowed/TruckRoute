import Foundation
import CoreLocation
import SwiftData

/// An entry in the address book. Loads point at these rather than carrying
/// their own address text, so a yard's address is typed once and its geocoded
/// coordinate is reused by every load that touches it.
@Model
final class Place {
    var name: String
    var address: String
    var notes: String
    /// Exactly one place is the yard every route starts from.
    var isHomeBase: Bool

    var latitude: Double?
    var longitude: Double?

    init(
        name: String = "",
        address: String = "",
        notes: String = "",
        isHomeBase: Bool = false
    ) {
        self.name = name
        self.address = address
        self.notes = notes
        self.isHomeBase = isHomeBase
    }

    var coordinate: CLLocationCoordinate2D? {
        get {
            guard let latitude, let longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        set {
            latitude = newValue?.latitude
            longitude = newValue?.longitude
        }
    }

    var displayName: String {
        name.isEmpty ? address : name
    }

    /// How many of `loads` would be left without an address if this one went.
    func loadsInUse(among loads: [Load]) -> Int {
        loads.filter { $0.pickup === self || $0.dropoff === self }.count
    }

    /// What deleting this address would actually cost, in a sentence fit to put
    /// in front of someone about to confirm it.
    ///
    /// Lives on the model rather than in a view because both the address list
    /// and the address form delete, and a warning that only one of them showed
    /// would be worse than none.
    func deletionWarning(among loads: [Load]) -> String {
        var warnings: [String] = []
        if isHomeBase {
            warnings.append("It's your home base — routes won't have a starting point until you pick a new one.")
        }
        let count = loadsInUse(among: loads)
        if count > 0 {
            warnings.append("\(count) load\(count == 1 ? "" : "s") use this address and will be left without one.")
        }
        return warnings.isEmpty ? "Nothing is using this address." : warnings.joined(separator: " ")
    }
}
