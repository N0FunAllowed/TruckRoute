import Foundation
import UIKit

/// Draws a planned route as a printable route sheet. Built on
/// `UIGraphicsPDFRenderer` rather than SwiftUI's own PDF snapshotting, since
/// that only ever captures a single page — a route with enough stops to run
/// off the bottom of a US Letter page would otherwise just get clipped.
enum RoutePDFRenderer {
    private static let pageSize = CGSize(width: 612, height: 792) // US Letter, points
    private static let margin: CGFloat = 36
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    private static let titleFont = UIFont.boldSystemFont(ofSize: 20)
    private static let headerFont = UIFont.boldSystemFont(ofSize: 13)
    private static let bodyFont = UIFont.systemFont(ofSize: 11)
    private static let smallFont = UIFont.systemFont(ofSize: 9)

    static func data(for route: PlannedRoute, unit: DistanceUnit, generatedAt: Date = .now) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        var cursor: CGFloat = margin

        func newPage(_ context: UIGraphicsPDFRendererContext) {
            context.beginPage()
            cursor = margin
        }

        func ensureSpace(for height: CGFloat, _ context: UIGraphicsPDFRendererContext) {
            if cursor + height > pageSize.height - margin {
                newPage(context)
            }
        }

        @discardableResult
        func draw(
            _ text: String,
            font: UIFont,
            color: UIColor = .black,
            spacingAfter: CGFloat = 4,
            _ context: UIGraphicsPDFRendererContext
        ) -> CGFloat {
            guard !text.isEmpty else { return 0 }
            let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let bounds = attributed.boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                context: nil
            )
            ensureSpace(for: bounds.height, context)
            attributed.draw(in: CGRect(x: margin, y: cursor, width: contentWidth, height: bounds.height))
            cursor += bounds.height + spacingAfter
            return bounds.height
        }

        return renderer.pdfData { context in
            newPage(context)
            draw("Route Sheet", font: titleFont, context)
            draw(
                "Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))",
                font: smallFont,
                color: .darkGray,
                spacingAfter: 16,
                context
            )

            for (index, stop) in route.stops.enumerated() {
                ensureSpace(for: 60, context) // keep one stop's block from splitting mid-entry when it fits
                // The load reference is what gets quoted at the gate, so the
                // printed sheet carries it just as the on-screen row does.
                let reference = stop.loadReference.map { " · \($0)" } ?? ""
                draw("\(index). \(stop.kind.label)\(reference) — \(stop.placeName)", font: headerFont, context)
                draw(stop.address, font: bodyFont, context)

                if stop.hasUnknownSchedule {
                    draw(
                        "Scheduled time unknown — the drive to this stop couldn't be measured",
                        font: bodyFont,
                        color: .systemOrange,
                        context
                    )
                } else if let arrival = stop.scheduledArrival {
                    let scheduleLine = "Scheduled \(arrival.formatted(date: .abbreviated, time: .shortened))"
                    draw(scheduleLine, font: bodyFont, color: stop.isLate ? .systemRed : .black, context)
                    if stop.isLate {
                        draw("⚠ After the deadline for this stop", font: bodyFont, color: .systemRed, context)
                    }
                }

                if let distance = stop.distance, let travelTime = stop.travelTime {
                    draw(
                        "Drive \(Format.distance(distance, in: unit)) · \(Format.duration(travelTime))",
                        font: bodyFont,
                        color: .darkGray,
                        context
                    )
                }

                if let rate = stop.loadRate, stop.kind == .dropoff {
                    draw("Pay \(Format.money(rate))", font: bodyFont, color: .darkGray, context)
                }

                cursor += 8
            }

            if !route.skipped.isEmpty {
                cursor += 8
                draw("Left out", font: headerFont, context)
                for skipped in route.skipped {
                    draw("• \(skipped.reference): \(skipped.reason)", font: bodyFont, context)
                }
            }

            let lateStops = route.stops.enumerated().filter { $0.element.isLate }
            let unknownStops = route.stops.enumerated().filter { $0.element.hasUnknownSchedule }
            if !lateStops.isEmpty || !unknownStops.isEmpty {
                cursor += 8
                draw("Scheduling warnings", font: headerFont, context)
                for (index, stop) in lateStops {
                    draw(
                        "• Stop \(index), \(stop.placeName): scheduled after its deadline.",
                        font: bodyFont,
                        color: .systemRed,
                        context
                    )
                }
                for (index, stop) in unknownStops {
                    draw(
                        "• Stop \(index), \(stop.placeName): no arrival time — the drive to it couldn't be measured.",
                        font: bodyFont,
                        color: .systemOrange,
                        context
                    )
                }
            }
        }
    }

    /// A filename unique enough that generating a second route sheet in the
    /// same share sheet session — or two taps close together — never
    /// collides with the first.
    static func suggestedFileName(generatedAt: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: generatedAt)
        let suffix = UUID().uuidString.prefix(4)
        return "TruckRoute-\(stamp)-\(suffix).pdf"
    }
}
