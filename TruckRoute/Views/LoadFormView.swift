import SwiftUI
import SwiftData

struct LoadFormView: View {
    /// Nil when adding a new load.
    let load: Load?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var reference = ""
    @State private var pickup: Place?
    @State private var dropoff: Place?
    @State private var pickupDate = Date.now
    @State private var hasPickupWindowEnd = false
    @State private var pickupWindowEnd = Date.now

    @State private var hasDeliveryDate = false
    @State private var deliveryDate = Date.now
    @State private var hasDeliveryWindow = false
    @State private var deliveryWindowStart = Date.now
    @State private var deliveryWindowEnd = Date.now

    @State private var serviceDurationMinutes = Load.defaultServiceDurationMinutes
    @State private var notes = ""
    @State private var rateText = ""

    /// `onAppear` fires again every time the place picker pops back to this
    /// form. Reloading the stored load then would throw away the place just
    /// picked, along with every other unsaved edit, so it only happens once.
    @State private var hasLoadedExisting = false

    @State private var isConfirmingDelete = false

    private var canSave: Bool {
        pickup != nil && dropoff != nil && scheduleError == nil && rateError == nil
    }

    /// Something was typed in the rate field but it isn't a number. Saving
    /// used to quietly store no rate at all.
    private var rateError: String? {
        guard !rateText.trimmed.isEmpty, MoneyInput.parse(rateText) == nil else { return nil }
        return "Rate isn't a number."
    }

    /// Concise, in-form validation for the handful of ways this schedule can
    /// contradict itself. Nil means the schedule is fine to save.
    private var scheduleError: String? {
        if hasPickupWindowEnd && pickupWindowEnd <= pickupDate {
            return "Pickup window must end after it starts."
        }
        if hasDeliveryWindow {
            if deliveryWindowEnd <= deliveryWindowStart {
                return "Delivery window must end after it starts."
            }
            if deliveryWindowStart < pickupDate {
                return "Delivery window can't start before pickup."
            }
            if hasDeliveryDate && deliveryWindowEnd > deliveryDate {
                return "Delivery window ends after the delivery deadline."
            }
        } else if hasDeliveryDate && deliveryDate < pickupDate {
            return "Delivery deadline is before pickup."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    NavigationLink {
                        PlacePicker(title: "Pick Up At", selection: $pickup)
                    } label: {
                        PlaceRowLabel(role: "Pick up at", place: pickup)
                    }
                    NavigationLink {
                        PlacePicker(title: "Drop Off At", selection: $dropoff)
                    } label: {
                        PlaceRowLabel(role: "Drop off at", place: dropoff)
                    }
                }

                if let pickup, pickup === dropoff {
                    Section {
                        Label("Pickup and drop-off are the same address.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    DatePicker("Pickup opens", selection: $pickupDate)
                    Toggle("Pickup window closes", isOn: $hasPickupWindowEnd.animation())
                    if hasPickupWindowEnd {
                        DatePicker("Closes", selection: $pickupWindowEnd)
                    }
                    Stepper(
                        "Time on site: \(serviceDurationMinutes) min",
                        value: $serviceDurationMinutes,
                        in: 0...480,
                        step: 15
                    )
                } header: {
                    Text("Pickup")
                } footer: {
                    Text("Arriving before the window opens just means waiting for it.")
                }

                Section {
                    Toggle("Delivery window", isOn: $hasDeliveryWindow.animation())
                    if hasDeliveryWindow {
                        DatePicker("Opens", selection: $deliveryWindowStart)
                        DatePicker("Closes", selection: $deliveryWindowEnd)
                    }
                    Toggle("Delivery deadline", isOn: $hasDeliveryDate.animation())
                    if hasDeliveryDate {
                        DatePicker("Deliver by", selection: $deliveryDate)
                    }
                } header: {
                    Text("Delivery")
                } footer: {
                    Text(hasDeliveryWindow
                        ? "The window is when the drop-off will actually accept the load; the deadline below is the hard cutoff."
                        : "A deadline alone is enough for most loads — add a window only if the drop-off also has fixed hours.")
                }

                if let scheduleError {
                    Section {
                        Label(scheduleError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField("Rate", text: $rateText)
                        .keyboardType(.decimalPad)
                    if let rateError {
                        Label(rateError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Pay")
                } footer: {
                    Text("What the load pays. The route works out your rate per mile across loaded and empty miles.")
                }

                Section("Details") {
                    TextField("Reference or customer", text: $reference)
                        .textInputAutocapitalization(.words)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }

                if load != nil {
                    Section {
                        Button("Delete load", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(load == nil ? "New Load" : "Edit Load")
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
            // Deleting from the list asks first; deleting from here used to
            // not, even though it's the same irreversible thing.
            .confirmationDialog(
                load.map { "Delete \($0.displayName)?" } ?? "",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let load {
                        context.delete(load)
                    }
                    dismiss()
                }
            }
            // Turning a window or deadline on used to seed it with "now",
            // which on any load more than a moment out is before the pickup —
            // so the form opened straight onto a validation error the user
            // had to clear by hand. Seed from the pickup instead, and only
            // when what's there doesn't already make sense.
            .onChange(of: hasPickupWindowEnd) { seedPickupWindow() }
            .onChange(of: hasDeliveryWindow) { seedDeliveryWindow() }
            .onChange(of: hasDeliveryDate) { seedDeliveryDeadline() }
        }
    }

    private func seedPickupWindow() {
        guard hasPickupWindowEnd, pickupWindowEnd <= pickupDate else { return }
        pickupWindowEnd = pickupDate.addingTimeInterval(2 * 3600)
    }

    private func seedDeliveryWindow() {
        guard hasDeliveryWindow else { return }
        if deliveryWindowStart < pickupDate {
            deliveryWindowStart = pickupDate.addingTimeInterval(4 * 3600)
        }
        if deliveryWindowEnd <= deliveryWindowStart {
            deliveryWindowEnd = deliveryWindowStart.addingTimeInterval(4 * 3600)
        }
        // Adding a window can push past a deadline that was fine without one.
        seedDeliveryDeadline()
    }

    private func seedDeliveryDeadline() {
        guard hasDeliveryDate else { return }
        // A window, where there is one, is the tighter constraint: the deadline
        // is the hard cutoff, so it can't land before the window closes.
        let floor = hasDeliveryWindow ? deliveryWindowEnd : pickupDate
        guard deliveryDate < floor else { return }
        deliveryDate = floor.addingTimeInterval(8 * 3600)
    }

    private func loadExisting() {
        guard let load, !hasLoadedExisting else { return }
        hasLoadedExisting = true
        reference = load.reference
        pickup = load.pickup
        dropoff = load.dropoff
        pickupDate = load.pickupDate
        notes = load.notes
        serviceDurationMinutes = load.serviceDurationMinutes
        if let rate = load.rate {
            rateText = MoneyInput.text(for: rate)
        }
        if let windowEnd = load.pickupWindowEnd {
            hasPickupWindowEnd = true
            pickupWindowEnd = windowEnd
        }
        if let delivery = load.deliveryDate {
            hasDeliveryDate = true
            deliveryDate = delivery
        }
        if let start = load.deliveryWindowStart, let end = load.deliveryWindowEnd {
            hasDeliveryWindow = true
            deliveryWindowStart = start
            deliveryWindowEnd = end
        }
    }

    private func save() {
        guard canSave else { return }

        let target = load ?? {
            let new = Load()
            context.insert(new)
            return new
        }()

        target.reference = reference.trimmed
        target.pickup = pickup
        target.dropoff = dropoff
        target.pickupDate = pickupDate
        target.pickupWindowEnd = hasPickupWindowEnd ? pickupWindowEnd : nil
        target.deliveryDate = hasDeliveryDate ? deliveryDate : nil
        target.deliveryWindowStart = hasDeliveryWindow ? deliveryWindowStart : nil
        target.deliveryWindowEnd = hasDeliveryWindow ? deliveryWindowEnd : nil
        target.serviceDurationMinutes = serviceDurationMinutes
        target.notes = notes
        target.rate = MoneyInput.parse(rateText)

        dismiss()
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
