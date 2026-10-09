import MapKit
import MoneyMatterKit
import SwiftUI

/// Picks a transaction's location: search for a place or tap the map to drop the pin.
struct TransactionLocationPickerSheet: View {
    let onSave: (TransactionLocation?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchFailed = false
    private let hadLocation: Bool

    init(location: TransactionLocation?, onSave: @escaping (TransactionLocation?) -> Void) {
        self.onSave = onSave
        hadLocation = location != nil
        let coordinate = location.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        _pin = State(initialValue: coordinate)
        if let coordinate {
            _camera = State(initialValue: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)))
        } else {
            _camera = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker("Transaction", systemImage: "mappin", coordinate: pin)
                    }
                }
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        withAnimation { pin = coordinate }
                    }
                }
            }
            .overlay(alignment: .top) {
                if !results.isEmpty || searchFailed {
                    searchResults
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(pin == nil ? "Search for a place or tap the map to drop a pin." : "Tap the map to move the pin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 8)
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search places")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { _, newValue in
                if newValue.isEmpty { results = []; searchFailed = false }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(pin.map { TransactionLocation(latitude: $0.latitude, longitude: $0.longitude) })
                        dismiss()
                    }
                    .disabled(pin == nil && !hadLocation)
                }
                if pin != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Remove Pin", systemImage: "mappin.slash", role: .destructive) {
                            withAnimation { pin = nil }
                        }
                    }
                }
            }
        }
    }

    private var searchResults: some View {
        List {
            if searchFailed {
                Text("No places found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(results, id: \.self) { item in
                Button {
                    select(item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? String(localized: "Unnamed Place"))
                            .foregroundStyle(.primary)
                        if let address = item.address?.shortAddress {
                            Text(address)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 280)
        .clipShape(.rect(cornerRadius: 16))
        .padding()
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        results = items
        searchFailed = items.isEmpty
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.location.coordinate
        withAnimation {
            pin = coordinate
            camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
            results = []
            searchFailed = false
        }
    }
}

/// A small non-interactive map with the transaction's pin; tapping opens it in Maps.
struct TransactionLocationPreview: View {
    let location: TransactionLocation

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800)),
            interactionModes: []) {
            Marker("Transaction", systemImage: "mappin", coordinate: coordinate)
        }
        .frame(height: 160)
        .clipShape(.rect(cornerRadius: 12))
        .onTapGesture { openInMaps() }
        .accessibilityElement()
        .accessibilityLabel("Transaction location map")
        .accessibilityHint("Opens the location in Maps")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openInMaps() }
    }

    private func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: location.latitude, longitude: location.longitude), address: nil)
        item.openInMaps()
    }
}
