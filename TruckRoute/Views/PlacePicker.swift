import SwiftUI
import SwiftData

/// Pick an address from the address book, or add one without leaving the form.
struct PlacePicker: View {
    let title: String
    @Binding var selection: Place?

    @Query(sort: \Place.name) private var places: [Place]
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var searchText = ""

    private var filteredPlaces: [Place] {
        guard !searchText.trimmed.isEmpty else { return places }
        return places.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.address.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if places.isEmpty {
                ContentUnavailableView(
                    "No addresses yet",
                    systemImage: "book.closed",
                    description: Text("Add one with the + button.")
                )
            } else if filteredPlaces.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
            ForEach(filteredPlaces) { place in
                Button {
                    selection = place
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.displayName).foregroundStyle(.primary)
                            Text(place.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection === place {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search addresses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New address", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            PlaceFormView(place: nil) { newPlace in
                selection = newPlace
            }
        }
    }
}

/// The row a form shows for a chosen place.
struct PlaceRowLabel: View {
    let role: String
    let place: Place?

    var body: some View {
        HStack {
            Text(role)
            Spacer()
            if let place {
                Text(place.displayName)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else {
                Text("Choose").foregroundStyle(.tertiary)
            }
        }
    }
}
