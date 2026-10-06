import SwiftUI
import SwiftData

struct LoadListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Load.pickupDate) private var loads: [Load]
    @State private var editing: Load?
    @State private var isAdding = false
    @State private var showDelivered = false
    @State private var pendingDeletion: Load?

    private var visibleLoads: [Load] {
        showDelivered ? loads : loads.filter { !$0.isDelivered }
    }

    /// What's still outstanding, so it's visible without planning a route.
    private var outstandingTotal: Double? {
        let rates = loads.filter { !$0.isDelivered }.compactMap(\.rate)
        return rates.isEmpty ? nil : rates.reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            Group {
                if loads.isEmpty {
                    ContentUnavailableView(
                        "No loads yet",
                        systemImage: "shippingbox",
                        description: Text("Add this week's loads and the Route tab will order them for you.")
                    )
                } else if visibleLoads.isEmpty {
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "checkmark.circle",
                        description: Text("Every load is delivered.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Loads")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add load", systemImage: "plus") { isAdding = true }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Toggle("Show delivered", isOn: $showDelivered)
                }
            }
            .sheet(isPresented: $isAdding) {
                LoadFormView(load: nil)
            }
            .sheet(item: $editing) { load in
                LoadFormView(load: load)
            }
            .confirmationDialog(
                pendingDeletion.map { "Delete \($0.displayName)?" } ?? "",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { load in
                Button("Delete", role: .destructive) { context.delete(load) }
            }
        }
    }

    private var list: some View {
        List {
            if let outstandingTotal {
                Section {
                    HStack {
                        Text("Outstanding")
                        Spacer()
                        Text(Format.money(outstandingTotal)).foregroundStyle(.green)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            ForEach(groupedByDay, id: \.day) { group in
                Section(Format.day(group.day)) {
                    ForEach(group.loads) { load in
                        Button {
                            editing = load
                        } label: {
                            LoadRow(load: load)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button(load.isDelivered ? "Mark planned" : "Mark delivered") {
                                load.isDelivered.toggle()
                            }
                            .tint(load.isDelivered ? .orange : .green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                pendingDeletion = load
                            }
                        }
                    }
                }
            }
        }
    }

    private var groupedByDay: [(day: Date, loads: [Load])] {
        let calendar = Calendar.current
        return Dictionary(grouping: visibleLoads) { calendar.startOfDay(for: $0.pickupDate) }
            .map { (day: $0.key, loads: $0.value.sorted { $0.pickupDate < $1.pickupDate }) }
            .sorted { $0.day < $1.day }
    }
}

private struct LoadRow: View {
    let load: Load

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !load.reference.isEmpty {
                Text(load.reference).font(.headline)
            }
            Label(load.pickup?.displayName ?? "No pickup set", systemImage: "arrow.up.circle")
            Label(load.dropoff?.displayName ?? "No drop-off set", systemImage: "arrow.down.circle")
            HStack(spacing: 6) {
                Text(load.pickupDate.formatted(date: .omitted, time: .shortened))
                if let rate = load.rate {
                    Text(Format.money(rate)).foregroundStyle(.green)
                }
                if load.isDelivered {
                    Label("Delivered", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .opacity(load.isDelivered ? 0.5 : 1)
    }
}
