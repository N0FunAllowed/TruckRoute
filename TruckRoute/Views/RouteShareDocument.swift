import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// What `ShareLink` hands to the share sheet for a planned route. The PDF is
/// rendered lazily inside the `DataRepresentation` closure — only when the
/// user actually shares, not on every view update — and each export gets its
/// own filename so sharing the same route twice doesn't collide in the share
/// sheet or in whatever the user saves it to.
struct RouteShareDocument: Transferable {
    let route: PlannedRoute
    let unit: DistanceUnit
    let generatedAt: Date

    init(route: PlannedRoute, unit: DistanceUnit, generatedAt: Date = .now) {
        self.route = route
        self.unit = unit
        self.generatedAt = generatedAt
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { document in
            RoutePDFRenderer.data(for: document.route, unit: document.unit, generatedAt: document.generatedAt)
        }
        .suggestedFileName { document in
            RoutePDFRenderer.suggestedFileName(generatedAt: document.generatedAt)
        }
    }
}
