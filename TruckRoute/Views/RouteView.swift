import SwiftUI
import SwiftData
import MapKit

struct RouteView: View {
    @Query(sort: \Load.pickupDate) private var allLoads: [Load]
    @Query private var places: [Place]
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.miles
    @State private var planner = RoutePlanner()

    private var homeBase: Place? {
        places.first(where: \.isHomeBase)
    }

    /// Delivered loads are done; routing only what's still outstanding is what
    /// keeps replanning meaningful as loads pile up over time.
    private var loads: [Load] {
        allLoads.filter { !$0.isDelivered }
    }

    var body: some View {
        NavigationStack {
            Group {
                if homeBase == nil {
                    ContentUnavailableView(
                        "Set your home base",
                        systemImage: "house",
                        description: Text("The route starts from your yard. Pick it in Settings.")
                    )
                } else if loads.isEmpty {
                    ContentUnavailableView(
                        "Nothing to route",
                        systemImage: "map",
                        description: Text("Add some loads first.")
                    )
                } else if let route = planner.route {
                    routeDetail(route)
                } else {
                    ContentUnavailableView {
                        Label("No route yet", systemImage: "map")
                    } description: {
                        Text("Plan a route for the \(loads.count) load\(loads.count == 1 ? "" : "s") on the board.")
                    } actions: {
                        Button("Plan route", action: planRoute)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Route")
            .toolbar {
                if let route = planner.route, !route.stops.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: RouteShareDocument(route: route, unit: unit),
                            preview: SharePreview("Route sheet")
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                if planner.route != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Replan", systemImage: "arrow.clockwise", action: planRoute)
                            .disabled(planner.isPlanning)
                    }
                }
            }
            .overlay {
                if planner.isPlanning {
                    ProgressView(planner.progressNote ?? "Planning…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .alert(
                "Couldn't plan the route",
                isPresented: Binding(
                    get: { planner.errorMessage != nil },
                    set: { if !$0 { planner.dismissError() } }
                )
            ) {
                Button("OK") { }
            } message: {
                Text(planner.errorMessage ?? "")
            }
        }
    }

    private func routeDetail(_ route: PlannedRoute) -> some View {
        List {
            Section {
                RouteMapView(stops: route.stops)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                    RouteStopRow(index: index, stop: stop, unit: unit)
                }
            } header: {
                Text("\(route.workingStopCount) stops")
            } footer: {
                RouteSummary(route: route, unit: unit)
            }

            if !route.skipped.isEmpty {
                Section("Left out") {
                    ForEach(route.skipped) { skipped in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skipped.reference).font(.subheadline.bold())
                            Text(skipped.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func planRoute() {
        guard let homeBase else { return }
        Task { await planner.plan(loads: loads, from: homeBase) }
    }
}

private struct RouteSummary: View {
    let route: PlannedRoute
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(Format.distance(route.totalDistance, in: unit)) · \(Format.duration(route.totalTravelTime)) driving")
            if route.emptyDistance > 0, let share = route.deadheadShare {
                Text("\(Format.distance(route.loadedDistance, in: unit)) loaded · \(Format.distance(route.emptyDistance, in: unit)) empty (\(Format.percent(share)) deadhead)")
            }
            if let total = route.totalRate, let perUnit = route.rate(per: unit) {
                Text("\(Format.money(total)) · \(Format.rate(perUnit, per: unit)) loaded + empty")
                    .fontWeight(.semibold)
            }
            if route.unmeasuredLegs > 0 {
                Text("\(route.unmeasuredLegs) leg\(route.unmeasuredLegs == 1 ? "" : "s") couldn't be measured, so these totals are low.")
                    .foregroundStyle(.orange)
            }
            if route.stopsWithUnknownSchedule > 0 {
                Text("\(route.stopsWithUnknownSchedule) stop\(route.stopsWithUnknownSchedule == 1 ? "" : "s") have no arrival time, because the drive to them couldn't be measured.")
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct RouteStopRow: View {
    let index: Int
    let stop: RouteStop
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let travelTime = stop.travelTime, let distance = stop.distance {
                HStack(spacing: 4) {
                    if stop.isDeadheadLeg {
                        Image(systemName: "arrow.right.to.line")
                        Text("Empty \(Format.distance(distance, in: unit)) · \(Format.duration(travelTime))")
                    } else {
                        Text("Loaded \(Format.distance(distance, in: unit)) · \(Format.duration(travelTime))")
                    }
                }
                .font(.caption)
                .foregroundStyle(stop.isDeadheadLeg ? Color.orange : Color.secondary)
            } else if index > 0 {
                Text("No driving route found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(index)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(color, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stop.kind.label)\(stop.loadReference.map { " · \($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(stop.placeName).font(.subheadline.bold())
                    Text(stop.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let day = stop.day {
                        Text(Format.day(day))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if stop.hasUnknownSchedule {
                        Label("Arrival unknown — drive time unavailable", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let arrival = stop.scheduledArrival {
                        Label(
                            Format.time(arrival, listedUnder: stop.day),
                            systemImage: stop.isLate ? "exclamationmark.triangle.fill" : "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(stop.isLate ? Color.red : Color.secondary)
                    }
                    if let rate = stop.loadRate, stop.kind == .dropoff {
                        Text(stop.rate(per: unit).map { "\(Format.money(rate)) · \(Format.rate($0, per: unit))" }
                            ?? Format.money(rate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                Button("Directions", systemImage: "arrow.triangle.turn.up.right.circle") {
                    openInMaps()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch stop.kind {
        case .start, .end: .gray
        case .pickup: .blue
        case .dropoff: .green
        }
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        item.name = stop.placeName.isEmpty ? stop.address : stop.placeName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}
