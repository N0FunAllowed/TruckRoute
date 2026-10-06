import Foundation
import SwiftData

@Model
final class Load {
    var reference: String
    var pickup: Place?
    var dropoff: Place?
    var pickupDate: Date
    /// When the pickup window closes. Nil means "any time at or after
    /// pickupDate" — arriving early just means waiting.
    var pickupWindowEnd: Date?
    var deliveryDate: Date?
    /// An actual delivery window, separate from the deliveryDate deadline
    /// above. When deliveryWindowEnd is nil, deliveryDate alone remains the
    /// deadline — existing loads with only a deadline keep working exactly
    /// as before.
    var deliveryWindowStart: Date?
    var deliveryWindowEnd: Date?
    /// How long the truck sits at each of this load's stops, in minutes.
    /// Declared with an inline default (not just in `init`) so SwiftData can
    /// lightweight-migrate existing rows that predate this field.
    var serviceDurationMinutes: Int = Load.defaultServiceDurationMinutes
    var notes: String
    /// What the load pays, before any costs. Nil when it isn't known yet.
    var rate: Double?
    /// Delivered loads are done — kept for the record, but out of the way of
    /// both the working list and route planning. Inline default for the
    /// same migration reason as `serviceDurationMinutes`: master already
    /// ships a `Load` without this field.
    var isDelivered: Bool = false

    static let defaultServiceDurationMinutes = 30

    init(
        reference: String = "",
        pickup: Place? = nil,
        dropoff: Place? = nil,
        pickupDate: Date = .now,
        pickupWindowEnd: Date? = nil,
        deliveryDate: Date? = nil,
        deliveryWindowStart: Date? = nil,
        deliveryWindowEnd: Date? = nil,
        serviceDurationMinutes: Int = Load.defaultServiceDurationMinutes,
        notes: String = "",
        rate: Double? = nil,
        isDelivered: Bool = false
    ) {
        self.reference = reference
        self.pickup = pickup
        self.dropoff = dropoff
        self.pickupDate = pickupDate
        self.pickupWindowEnd = pickupWindowEnd
        self.deliveryDate = deliveryDate
        self.deliveryWindowStart = deliveryWindowStart
        self.deliveryWindowEnd = deliveryWindowEnd
        self.serviceDurationMinutes = serviceDurationMinutes
        self.notes = notes
        self.rate = rate
        self.isDelivered = isDelivered
    }

    var displayName: String {
        if !reference.isEmpty { return reference }
        let from = pickup?.displayName ?? "?"
        let to = dropoff?.displayName ?? "?"
        return "\(from) → \(to)"
    }
}
