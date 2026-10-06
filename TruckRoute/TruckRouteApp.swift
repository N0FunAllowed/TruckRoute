import SwiftUI
import SwiftData

@main
struct TruckRouteApp: App {
    /// Built once, by hand, rather than with `.modelContainer(for:)`.
    ///
    /// That modifier traps when the store can't be opened — a schema change
    /// lightweight migration can't handle, a full disk, a file the OS won't
    /// hand back — and a trap on launch is a crash with nothing on screen to
    /// explain it or to report. Holding the failure instead lets the app come
    /// up and say what went wrong.
    private let container: Result<ModelContainer, Error>

    init() {
        container = Result { try ModelContainer(for: Load.self, Place.self) }
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure(let error):
                StoreUnavailableView(error: error)
            }
        }
    }
}

/// Shown only when the saved data can't be opened at all. Deliberately offers
/// no "start fresh" button: wiping the week's loads is not a thing to put one
/// tap away from someone who has just been told something is broken.
struct StoreUnavailableView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("Can't open your data", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("TruckRoute couldn't open its saved loads and addresses, so it's stopped rather than risk losing them. Reopening the app is worth a try; if it keeps happening, send this along:\n\n\(error.localizedDescription)")
        }
        .padding()
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            LoadListView()
                .tabItem { Label("Loads", systemImage: "shippingbox") }
            RouteView()
                .tabItem { Label("Route", systemImage: "map") }
            PlaceListView()
                .tabItem { Label("Addresses", systemImage: "book.closed") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
