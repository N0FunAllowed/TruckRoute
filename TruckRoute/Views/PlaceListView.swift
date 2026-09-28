import SwiftUI
import SwiftData

struct PlaceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Place.name) private var places: [Place]
    @Query private var loads: [Load]

    @State private var editing: Place?
    @State private var isAdding = false
    @State private var pendingDeletion: Place?

    var body: some View {
        NavigationStack {
            Group {
                if places.isEmpty {
                    ContentUnavailableView(
                        "No addresses yet",
                        systemImage: "book.closed",
                        description: Text("Add the yards, customers and docks you run to. Loads pick from this list.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Addresses")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add address", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) { PlaceFormView(place: nil) }
            .sheet(item: $editing) { PlaceFormView(place: $0) }
            .confirmationDialog(
                pendingDeletion.map { "Delete \($0.displayName)?" } ?? "",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { place in
                Button("Delete", role: .destructive) { context.delete(place) }
            } message: { place in
                Text(deletionWarning(for: place))
            }
        }
    }

    private var list: some View {
        List {
            ForEach(places) { place in
                Button {
                    editing = place
                } label: {
                    PlaceRow(place: place)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDeletion = place }
                }
            }
        }
    }

    private func loadsUsing(_ place: Place) -> Int {
        loads.filter { $0.pickup === place || $0.dropoff === place }.count
    }

    private func deletionWarning(for place: Place) -> String {
        var warnings: [String] = []
        if place.isHomeBase {
            warnings.append("It's your home base — routes won't have a starting point until you pick a new one.")
        }
        let count = loadsUsing(place)
        if count > 0 {
            warnings.append("\(count) load\(count == 1 ? "" : "s") use this address and will be left without one.")
        }
        return warnings.isEmpty ? "Nothing is using this address." : warnings.joined(separator: " ")
    }
}

private struct PlaceRow: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(place.displayName).font(.headline)
                if place.isHomeBase {
                    Image(systemName: "house.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            Text(place.address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
