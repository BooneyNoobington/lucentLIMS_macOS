import SwiftUI
import MapKit
import Charts

/// Spots and sites on a map, as in lucentAndShiny's "Locations" tab.
struct LocationsView: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @State private var position = MapCameraPosition.region(LocationsView.karlsruhe)
    @State private var showsInspector = !Platform.isPhone

    static let karlsruhe = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.0135, longitude: 8.3850),
        span: MKCoordinateSpan(latitudeDelta: 0.065, longitudeDelta: 0.19))

    static func region(for site: Site) -> MKCoordinateRegion {
        let latitudes = site.border.map(\.latitude), longitudes = site.border.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (latitudes.min()! + latitudes.max()!) / 2,
                                            longitude: (longitudes.min()! + longitudes.max()!) / 2)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: (latitudes.max()! - latitudes.min()!) * 2.2,
                                                         longitudeDelta: (longitudes.max()! - longitudes.min()!) * 2.2))
    }

    var body: some View {
        @Bindable var navigation = navigation

        Map(position: $position, selection: $navigation.locationSelection) {
            ForEach(store.sites) { site in
                MapPolygon(coordinates: site.border.map(\.coordinate))
                    .foregroundStyle(Color.accentColor.opacity(navigation.locationSelection == .site(site.id) ? 0.35 : 0.15))
                    .stroke(Color.accentColor, lineWidth: 2)
                Marker(site.name, systemImage: "square.dashed", coordinate: site.center.coordinate)
                    .tint(Color.accentColor)
                    .tag(LocationRef.site(site.id))
            }
            ForEach(store.spots.filter { $0.point != nil }) { spot in
                let matrix = store.primaryMatrix(at: .spot(spot.id))
                Marker(spot.name, systemImage: matrix?.systemImage ?? "mappin", coordinate: spot.point!.coordinate)
                    .tint(matrix?.tint ?? .red)
                    .tag(LocationRef.spot(spot.id))
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
            #if os(macOS)
            MapZoomStepper()
            #endif
        }
        .onChange(of: navigation.locationSelection, initial: true) { _, selection in
            focus(on: selection)
            if selection != nil { showsInspector = true }
        }
        .navigationTitle("Locations")
        .toolbar {
            ToolbarItem {
                Button("Show All", systemImage: "scope") {
                    navigation.locationSelection = nil
                    withAnimation(.smooth(duration: 0.8)) { position = .region(Self.karlsruhe) }
                }
            }
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.trailing") { showsInspector.toggle() }
            }
        }
        .inspector(isPresented: $showsInspector) {
            LocationInspector()
                .inspectorColumnWidth(min: 340, ideal: 400, max: 560)
        }
    }

    private func focus(on selection: LocationRef?) {
        guard let selection else { return }
        withAnimation(.smooth(duration: 0.8)) {
            switch selection {
            case .spot(let id):
                if let point = store.spot(id)?.point {
                    position = .camera(MapCamera(centerCoordinate: point.coordinate, distance: 2500, pitch: 45))
                }
            case .site(let id):
                if let site = store.site(id) { position = .region(Self.region(for: site)) }
            }
        }
    }
}

private struct LocationInspector: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        if let selection = navigation.locationSelection {
            LocationDetailView(location: selection)
                .id(selection)
        } else {
            List {
                Section("Spots") {
                    ForEach(store.spots) { spot in
                        row(.spot(spot.id), title: spot.name, subtitle: spot.description)
                    }
                }
                Section("Sites") {
                    ForEach(store.sites) { site in
                        row(.site(site.id), title: site.name, subtitle: site.address?.line1 ?? site.description)
                    }
                }
            }
        }
    }

    private func row(_ location: LocationRef, title: String, subtitle: String) -> some View {
        let matrix = store.primaryMatrix(at: location)
        let isSite = if case .site = location { true } else { false }
        return Button {
            navigation.locationSelection = location
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSite ? "square.dashed" : matrix?.systemImage ?? "mappin")
                    .foregroundStyle(isSite ? Color.accentColor : matrix?.tint ?? .red)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(store.collections(at: location).count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LocationDetailView: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    let location: LocationRef
    @State private var parameterID: Int?

    var body: some View {
        let collections = store.collections(at: location)
        let parameters = store.measuredParameters(at: location)

        Form {
            Section {
                Button("All Locations", systemImage: "chevron.left") { navigation.locationSelection = nil }
                    .buttonStyle(.borderless)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(description)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if let parameter = parameters.first(where: { $0.id == parameterID }) ?? mostExceeded(parameters) {
                Section("Time series") {
                    Picker("Parameter", selection: Binding(get: { parameter.id }, set: { parameterID = $0 })) {
                        ForEach(parameters) { Text($0.name).tag($0.id) }
                    }
                    SeriesChart(points: store.series(at: location, for: parameter), parameter: parameter)
                        .padding(.vertical, 6)
                }
            }

            switch location {
            case .spot(let id):
                if let spot = store.spot(id) { spotSection(spot) }
            case .site(let id):
                if let site = store.site(id) { siteSection(site) }
            }

            Section("Collections") {
                LabeledContent("Count", value: "\(collections.count)")
                if let last = collections.map(\.sampledAt).max() {
                    LabeledContent("Last sampled", value: last.formatted(.relative(presentation: .named)))
                }
                if let matrix = store.primaryMatrix(at: location) {
                    LabeledContent("Matrix") { MatrixLabel(matrix: matrix) }
                }
                Button("Show in Collections", systemImage: "testtube.2") {
                    navigation.showCollections(matching: title)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The chart opens on the parameter that exceeded its limits most often here.
    private func mostExceeded(_ parameters: [Parameter]) -> Parameter? {
        let counts = parameters.map { parameter in
            (parameter, store.series(at: location, for: parameter).filter(\.exceeded).count)
        }
        guard let top = counts.max(by: { $0.1 < $1.1 }), top.1 > 0 else { return parameters.first }
        return top.0
    }

    private var title: String {
        switch location {
        case .spot(let id): store.spot(id)?.name ?? "—"
        case .site(let id): store.site(id)?.name ?? "—"
        }
    }

    private var description: String {
        switch location {
        case .spot(let id): store.spot(id)?.description ?? ""
        case .site(let id): store.site(id)?.description ?? ""
        }
    }

    @ViewBuilder
    private func spotSection(_ spot: Spot) -> some View {
        Section("Position") {
            LabeledContent("x (latitude)", value: spot.x?.formatted(.number.precision(.fractionLength(6))) ?? "—")
            LabeledContent("y (longitude)", value: spot.y?.formatted(.number.precision(.fractionLength(6))) ?? "—")
            if let crs = store.referenceSystem(spot.crsID) {
                LabeledContent("Reference system", value: crs.epsg.map { "\(crs.name) (EPSG:\(String($0)))" } ?? crs.name)
            }
            if let site = store.site(spot.siteID) {
                LabeledContent("Site") {
                    Button(site.name) { navigation.locationSelection = .site(site.id) }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func siteSection(_ site: Site) -> some View {
        Section("Site") {
            if let address = site.address {
                LabeledContent("Address") {
                    VStack(alignment: .trailing) {
                        Text(address.line1)
                        Text(address.line2)
                    }
                }
            }
            LabeledContent("Border", value: String(localized: "Polygon, \(site.border.count) vertices"))
            ForEach(store.spots(in: site)) { spot in
                LabeledContent("Spot") {
                    Button(spot.name) { navigation.locationSelection = .spot(spot.id) }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// A parameter over time with its limits; hover or drag to read single values.
struct SeriesChart: View {
    @Environment(LabStore.self) private var store
    let points: [SeriesPoint]
    let parameter: Parameter
    @State private var selectedDate: Date?

    private var selected: SeriesPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    /// Each limit once, with the documents that set it.
    private var limits: [(value: Double, documents: String)] {
        let thresholds = Set(points.flatMap(\.limits))
        let byValue = Dictionary(grouping: thresholds.flatMap { threshold in
            [threshold.lowerLimit, threshold.upperLimit].compactMap { $0 }.map { ($0, threshold.documentID) }
        }, by: \.0)
        return byValue.map { value, pairs in
            (value, Set(pairs.map(\.1)).sorted().compactMap { store.document($0)?.shortName }.joined(separator: ", "))
        }
        .sorted { $0.value < $1.value }
    }

    var body: some View {
        let unit = store.unit(parameter.unitID)?.symbol ?? ""
        let name = parameter.name

        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value(name, point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                PointMark(x: .value("Date", point.date), y: .value(name, point.value))
                    .foregroundStyle(point.exceeded ? Color.red : Color.accentColor)
                    .symbolSize(point.exceeded ? 60 : 25)
            }
            ForEach(limits, id: \.value) { limit in
                RuleMark(y: .value("Limit", limit.value))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Limit \(limit.value.formatted()) \(unit) · \(limit.documents)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
            }
            if let selected {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.format(.decimal(selected.value), unitID: parameter.unitID))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(selected.exceeded ? .red : .primary)
                            Text(selected.date, format: .dateTime.day().month().year())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let collection = store.collection(selected.collectionID) {
                                IdentifierView(identifier: collection.name)
                                    .font(.caption2)
                            }
                        }
                        .padding(8)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(unit)
        .frame(height: 220)
    }
}
