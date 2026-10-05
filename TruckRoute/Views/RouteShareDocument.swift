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

    /// Set only by tests that need a fixed timestamp. Left nil in the app so
    /// the sheet is stamped when it's actually exported: `ShareLink` rebuilds
    /// this value on every view update, so capturing `.now` here would print
    /// whenever the Route tab last redrew, which can be a long time before
    /// anyone taps Share.
    private let pinnedDate: Date?

    init(route: PlannedRoute, unit: DistanceUnit, generatedAt: Date? = nil) {
        self.route = route
        self.unit = unit
        self.pinnedDate = generatedAt
    }

    var generatedAt: Date { pinnedDate ?? .now }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { document in
            RoutePDFRenderer.data(for: document.route, unit: document.unit, generatedAt: document.generatedAt)
        }
        .suggestedFileName { document in
            RoutePDFRenderer.suggestedFileName(generatedAt: document.generatedAt)
        }
    }
}
