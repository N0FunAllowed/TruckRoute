import SwiftUI
import SwiftData
import MapKit

struct PlaceFormView: View {
    /// Nil when adding a new place.
    let place: Place?
    /// Called with the saved place, so a load form can select what it just added.
    var onSave: ((Place) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Only so deleting from here can warn about what's using this address,
    /// exactly as deleting from the list does.
    @Query private var loads: [Load]

    @State private var isConfirmingDelete = false

    @State private var name = ""
    @State private var address = ""
    @State private var notes = ""

    @State private var completer = AddressCompleter()
    @State private var confirmed: CLLocationCoordinate2D?
    @State private var isLookingUp = false
    @State private var lookupError: String?
    /// Set while filling the address in from a suggestion, so the onChange
    /// below doesn't throw away the coordinate that came with it.
    @State private var isApplyingSuggestion = false

    private var canSave: Bool { !address.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(2...)
                        .onChange(of: address) { _, newValue in
                            if isApplyingSuggestion {
                                isApplyingSuggestion = false
                                return
                            }
                            confirmed = nil
                            lookupError = nil
                            completer.update(query: newValue)
                        }
                } footer: {
                    Text("Start typing and pick a suggestion to confirm it's a real place.")
                }
                .textInputAutocapitalization(.words)

                if !completer.suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(completer.suggestions, id: \.self) { suggestion in
                            Button {
                                select(suggestion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .foregroundStyle(.primary)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                confirmationSection

                Section("Notes") {
                    TextField("Gate code, dock hours, contact", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }

                if place != nil {
                    Section {
                        Button("Delete address", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(place == nil ? "New Address" : "Edit Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: loadExisting)
            // Deleting from the list asks first and says what's using the
            // address; deleting from here used to do neither.
            .confirmationDialog(
                place.map { "Delete \($0.displayName)?" } ?? "",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let place {
                        context.delete(place)
                    }
                    dismiss()
                }
            } message: {
                if let place {
                    Text(place.deletionWarning(among: loads))
                }
            }
        }
    }

    @ViewBuilder
    private var confirmationSection: some View {
        if let confirmed {
            Section {
                MapPreview(coordinate: confirmed, title: name.isEmpty ? address : name)
                    .frame(height: 150)
                    .listRowInsets(EdgeInsets())
                Label("Found on the map", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        } else if !address.trimmed.isEmpty {
            Section {
                Button {
                    lookUpTypedAddress()
                } label: {
                    if isLookingUp {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Checking…")
                        }
                    } else {
                        Label("Check this address", systemImage: "mappin.and.ellipse")
                    }
                }
                .disabled(isLookingUp)

                if let lookupError {
                    Label(lookupError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            } footer: {
                Text("You can save without checking — the address gets looked up when you plan a route.")
            }
        }
    }

    private func loadExisting() {
        guard let place else { return }
        name = place.name
        // Setting address fires onChange, which would otherwise treat this
        // like a fresh edit and wipe the coordinate right back out below.
        isApplyingSuggestion = true
        address = place.address
        notes = place.notes
        confirmed = place.coordinate
    }

    private func select(_ suggestion: MKLocalSearchCompletion) {
        Task {
            guard let item = await completer.resolve(suggestion) else {
                lookupError = "Couldn't look that one up. Try another."
                return
            }
            if name.trimmed.isEmpty, let itemName = item.name {
                name = itemName
            }
            isApplyingSuggestion = true
            address = item.placemark.title ?? suggestion.title
            confirmed = item.placemark.coordinate
            completer.clear()
        }
    }

    private func lookUpTypedAddress() {
        isLookingUp = true
        lookupError = nil
        let lookedUp = address
        Task {
            defer { isLookingUp = false }
            do {
                let coordinate = try await GeocodingService.shared.coordinate(for: lookedUp.trimmed)
                // The field stays editable while this runs. If the address
                // changed meanwhile, this coordinate is for the old text, and
                // saving it against the new one would route to the wrong place.
                guard address == lookedUp else { return }
                confirmed = coordinate
                completer.clear()
            } catch {
                guard address == lookedUp else { return }
                lookupError = error.localizedDescription
            }
        }
    }

    private func save() {
        let target = place ?? {
            let new = Place()
            context.insert(new)
            return new
        }()

        target.name = name.trimmed
        target.address = address.trimmed
        target.notes = notes
        // Keep a coordinate we already confirmed; otherwise drop a stale one so
        // the planner looks the new address up.
        target.coordinate = confirmed

        onSave?(target)
        dismiss()
    }
}

private struct MapPreview: View {
    let coordinate: CLLocationCoordinate2D
    let title: String

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            ),
            interactionModes: []
        ) {
            Marker(title, coordinate: coordinate)
        }
        .id("\(coordinate.latitude),\(coordinate.longitude)")
    }
}
