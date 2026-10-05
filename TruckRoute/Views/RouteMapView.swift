import SwiftUI
import MapKit

struct RouteMapView: View {
    let stops: [RouteStop]

    /// `Map(initialPosition:)` only ever applies on first appearance, so a
    /// replanned route used to be drawn under the old route's camera — a
    /// different week's stops, off-screen. Driving the camera from state and
    /// re-fitting when the stop list changes identity fixes that while still
    /// leaving the user free to pan and zoom.
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                Marker("\(index). \(stop.placeName)", coordinate: stop.coordinate)
                    .tint(tint(for: stop.kind))

                if let polyline = stop.polyline {
                    if stop.isDeadheadLeg {
                        MapPolyline(polyline)
                            .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                    } else {
                        MapPolyline(polyline)
                            .stroke(.blue, lineWidth: 4)
                    }
                }
            }
        }
        .mapControlVisibility(.hidden)
        .onAppear { position = .region(region) }
        // Keyed on the stops' identities, not the stops themselves: measuring
        // legs republishes the route once per leg to fill in polylines, and
        // yanking the camera back mid-measurement would be worse than not
        // re-fitting at all. Identities only change when a route is replanned.
        .onChange(of: stops.map(\.id)) {
            position = .region(region)
        }
    }

    private func tint(for kind: StopKind) -> Color {
        switch kind {
        case .start, .end: .gray
        case .pickup: .blue
        case .dropoff: .green
        }
    }

    private var region: MKCoordinateRegion {
        let coordinates = stops.map(\.coordinate)
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
            )
        }

        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.05)
            )
        )
    }
}
