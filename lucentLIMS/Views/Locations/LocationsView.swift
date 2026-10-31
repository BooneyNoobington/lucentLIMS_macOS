import SwiftUI
import MapKit
import Charts

/// Spots and sites on a map, as in lucentAndShiny's "Locations" tab.
struct LocationsView: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @State private var position = MapCameraPosition.region(LocationsView.karlsruhe)
    @State private var showsInspector = !Platform.isPhone
    @State private var visibleRegion: MKCoordinateRegion?

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
        let draft = navigation.locationDraft

        MapReader { proxy in
            Map(position: $position, selection: draft == nil ? $navigation.locationSelection : .constant(nil)) {
                ForEach(store.sites.filter { draft?.editing != .site($0.id) }) { site in
                    MapPolygon(coordinates: site.border.map(\.coordinate))
                        .foregroundStyle(Color.accentColor.opacity(navigation.locationSelection == .site(site.id) ? 0.35 : 0.15))
                        .stroke(Color.accentColor, lineWidth: 2)
                    Marker(site.name, systemImage: "square.dashed", coordinate: site.center.coordinate)
                        .tint(Color.accentColor)
                        .tag(LocationRef.site(site.id))
                }
                ForEach(store.spots.filter { $0.point != nil && draft?.editing != .spot($0.id) }) { spot in
                    let matrix = store.primaryMatrix(at: .spot(spot.id))
                    Marker(spot.name, systemImage: matrix?.systemImage ?? "mappin", coordinate: spot.point!.coordinate)
                        .tint(matrix?.tint ?? .red)
                        .tag(LocationRef.spot(spot.id))
                }
                if let draft {
                    DraftOnMap(draft: draft, proxy: proxy) { index, point in
                        navigation.locationDraft?.border[index] = point
                    } remove: { index in
                        navigation.locationDraft?.border.remove(at: index)
                    }
                }
            }
            .mapStyle(.standard(elevation: draft == nil ? .realistic : .flat, pointsOfInterest: .excludingAll))
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                guard navigation.locationDraft != nil, let coordinate = proxy.convert(tap.location, from: .local) else {
                    return
                }
                add(GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
            })
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            #if os(macOS)
            MapZoomStepper()
            #endif
        }
        .onMapCameraChange { context in visibleRegion = context.region }
        .overlay(alignment: .top) {
            if let draft { DrawingHint(draft: draft).padding(.top, 12) }
        }
        .onChange(of: navigation.locationSelection, initial: true) { _, selection in
            focus(on: selection)
            if selection != nil { showsInspector = true }
        }
        .onChange(of: draft?.point) { _, point in
            // A spot inside a site's border belongs to that site.
            if let point { navigation.locationDraft?.siteID = store.site(containing: point)?.id }
        }
        .onAppear {
            #if DEBUG
            // -editSite <id> names the site only; its border comes from the store.
            if case .site(let id) = draft?.editing, draft?.border.isEmpty == true, let site = store.site(id) {
                navigation.locationDraft = LocationDraft(editing: site)
            }
            #endif
            if let draft = navigation.locationDraft { showDraft(draft) }
        }
        .navigationTitle("Locations")
        .toolbar {
            ToolbarItem {
                Menu("Add", systemImage: "plus") {
                    Button("New Spot", systemImage: "mappin.and.ellipse") { startDrawing(.spot) }
                    Button("New Site", systemImage: "square.dashed") { startDrawing(.site) }
                }
                .disabled(!store.can(.sampler) || draft != nil)
                .help(store.can(.sampler) ? "Add a spot or a site" : "Needs the sampler role")
            }
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
                #if os(iOS)
                // On an iPhone the inspector is a sheet; a low one leaves the map free to draw on.
                .presentationDetents([.fraction(0.35), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                #endif
        }
    }

    private func startDrawing(_ kind: LocationDraft.Kind) {
        navigation.locationSelection = nil
        navigation.locationDraft = LocationDraft(kind: kind)
        showsInspector = true
        // Drawing works on a flat map, seen from straight above.
        withAnimation(.smooth(duration: 0.5)) { position = .region(visibleRegion ?? Self.karlsruhe) }
    }

    private func add(_ point: GeoPoint) {
        switch navigation.locationDraft?.kind {
        case .spot: navigation.locationDraft?.point = point
        case .site: navigation.locationDraft?.addCorner(point)
        case nil: break
        }
    }

    private func showDraft(_ draft: LocationDraft) {
        let points = draft.border + [draft.point].compactMap { $0 }
        guard !points.isEmpty else { return }
        let site = Site(id: 0, name: "", description: "", border: points)
        var region = points.count > 1 ? Self.region(for: site)
            : MKCoordinateRegion(center: points[0].coordinate, latitudinalMeters: 900, longitudinalMeters: 900)
        if Platform.isPhone {
            // The inspector sheet covers the lower third: the drawing goes into the part above it.
            region.span.latitudeDelta *= 1.4
            region.span.longitudeDelta *= 1.4
            region.center.latitude -= region.span.latitudeDelta * 0.2
        }
        position = .region(region)
        showsInspector = true
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
        if let draft = navigation.locationDraft {
            LocationEditor(draft: draft)
        } else if let selection = navigation.locationSelection {
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
                HStack {
                    Button("All Locations", systemImage: "chevron.left") { navigation.locationSelection = nil }
                    Spacer()
                    Button("Edit", systemImage: "pencil") { edit() }
                        .disabled(!store.can(.sampler))
                        .help(store.can(.sampler) ? "Rename it, move it or redraw its border" : "Needs the sampler role")
                }
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

    private func edit() {
        switch location {
        case .spot(let id): if let spot = store.spot(id) { navigation.locationDraft = LocationDraft(editing: spot) }
        case .site(let id): if let site = store.site(id) { navigation.locationDraft = LocationDraft(editing: site) }
        }
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

// MARK: - Drawing

/// The spot or site being drawn, in the colour of work in progress.
private struct DraftOnMap: MapContent {
    let draft: LocationDraft
    let proxy: MapProxy
    /// A corner dragged to a new place.
    let move: (Int, GeoPoint) -> Void
    let remove: (Int) -> Void

    var body: some MapContent {
        if draft.kind == .spot, let point = draft.point {
            Marker(draft.name.isEmpty ? String(localized: "New spot") : draft.name, systemImage: "mappin",
                   coordinate: point.coordinate)
                .tint(.orange)
        }
        if draft.kind == .site {
            if draft.border.count >= 3 {
                MapPolygon(coordinates: draft.border.map(\.coordinate))
                    .foregroundStyle(Color.orange.opacity(0.2))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            } else if draft.border.count == 2 {
                MapPolyline(coordinates: draft.border.map(\.coordinate))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            ForEach(Array(draft.border.enumerated()), id: \.offset) { index, corner in
                Annotation(String(index + 1), coordinate: corner.coordinate, anchor: .center) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.orange, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .padding(6)  // a larger target to grab
                        .contentShape(Circle())
                        .highPriorityGesture(DragGesture(coordinateSpace: .global).onChanged { drag in
                            if let coordinate = proxy.convert(drag.location, from: .global) {
                                move(index, GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
                            }
                        })
                        .contextMenu {
                            Button("Remove Corner", systemImage: "minus.circle", role: .destructive) { remove(index) }
                                .disabled(draft.border.count <= 3)
                        }
                        .help("Drag to move this corner")
                }
                .annotationTitles(.hidden)
            }
        }
    }
}

/// What to do next, over the map.
private struct DrawingHint: View {
    let draft: LocationDraft

    var body: some View {
        Label(text, systemImage: draft.kind == .spot ? "hand.point.up.left" : "pencil.and.outline")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private var text: String {
        #if os(macOS)
        let action = String(localized: "Click")
        #else
        let action = String(localized: "Tap")
        #endif
        switch draft.kind {
        case .spot:
            return draft.point == nil ? String(localized: "\(action) the map where the spot is")
                : String(localized: "\(action) again to move the spot")
        case .site where draft.editing != nil && draft.border.count >= 3:
            return String(localized: "Drag corners · \(action) an edge to add one")
        case .site:
            return draft.border.isEmpty ? String(localized: "\(action) the map at each corner of the site")
                : String(localized: "\(action) the next corner · \(draft.border.count) so far")
        }
    }
}

/// The name and coordinates of the spot or site being drawn.
private struct LocationEditor: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @State private var saving = false
    @State private var error: String?
    /// A coordinate typed before the other one: a spot needs both.
    @State private var typedLatitude: Double?
    @State private var typedLongitude: Double?
    /// The drawing as last seen, shown while the editor goes away.
    @State private var lastDraft: LocationDraft

    init(draft: LocationDraft) {
        _lastDraft = State(initialValue: draft)
    }

    /// The drawing, without trapping once it has ended: after Cancel or Save set it to nil, SwiftUI
    /// updates the fields once more, and a text field may still write its last words.
    private var draft: Binding<LocationDraft> {
        Binding {
            navigation.locationDraft ?? lastDraft
        } set: { value in
            if navigation.locationDraft != nil { navigation.locationDraft = value }
        }
    }

    var body: some View {
        let draft = self.draft
        Group {
            let kind = draft.wrappedValue.kind
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(draft.wrappedValue))
                            .font(.title2.weight(.semibold))
                        Text(kind == .spot ? "A point where samples are taken." : "An area, drawn by its border.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Name") {
                    TextField("Name", text: draft.name, prompt: Text(kind == .spot ? "e.g. Pegel Rheinhafen" : "e.g. Rheinhafen"))
                    TextField("Description", text: draft.description, prompt: Text("Optional, e.g. Am Steg"))
                }

                switch kind {
                case .spot:
                    Section {
                        TextField("Latitude", value: coordinate(\.latitude, draft: draft),
                                  format: .number.precision(.fractionLength(0...6)), prompt: Text("e.g. 49.014100"))
                        TextField("Longitude", value: coordinate(\.longitude, draft: draft),
                                  format: .number.precision(.fractionLength(0...6)), prompt: Text("e.g. 8.329000"))
                        Picker("Site", selection: draft.siteID) {
                            Text("None").tag(Int?.none)
                            ForEach(store.sites) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } header: {
                        Text("Position")
                    } footer: {
                        Text("Place it on the map or type its coordinates (WGS 84). A spot inside a site's border belongs to that site.")
                    }
                case .site:
                    Section {
                        ForEach(Array(draft.wrappedValue.border.enumerated()), id: \.offset) { index, corner in
                            LabeledContent("Corner \(index + 1)") {
                                HStack(spacing: 8) {
                                    Text(corner.latitude, format: .number.precision(.fractionLength(5)))
                                        + Text(", ")
                                        + Text(corner.longitude, format: .number.precision(.fractionLength(5)))
                                    Button("Remove Corner \(index + 1)", systemImage: "minus.circle") {
                                        draft.wrappedValue.border.remove(at: index)
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.red)
                                }
                            }
                            .monospacedDigit()
                        }
                        HStack {
                            Button("Undo Last Corner", systemImage: "arrow.uturn.backward") {
                                draft.wrappedValue.border.removeLast()
                            }
                            .disabled(draft.wrappedValue.border.isEmpty)
                            Spacer()
                            Button("Start Over", role: .destructive) { draft.wrappedValue.border.removeAll() }
                                .disabled(draft.wrappedValue.border.isEmpty)
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        Text("Border")
                    } footer: {
                        Text(draft.wrappedValue.editing == nil
                             ? "Place the corners in order around the area; the last one joins the first."
                             : "Drag corners on the map to move them; a click near an edge adds a corner there.")
                    }
                }

                if let problem = draft.wrappedValue.problem {
                    Section {
                        Label(problem, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Cancel") { navigation.locationDraft = nil }
                    Spacer()
                    Button(draft.wrappedValue.editing != nil ? "Save" : kind == .spot ? "Add Spot" : "Add Site") {
                        save(draft.wrappedValue)
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(saving || draft.wrappedValue.problem != nil || !store.can(.sampler))
                }
                .padding(12)
                .background(.bar)
            }
        }
        .onChange(of: navigation.locationDraft) { _, current in
            if let current { lastDraft = current }
        }
    }

    private func title(_ draft: LocationDraft) -> String {
        switch (draft.kind, draft.editing) {
        case (.spot, nil): String(localized: "New Spot")
        case (.site, nil): String(localized: "New Site")
        case (.spot, _): String(localized: "Edit Spot")
        case (.site, _): String(localized: "Edit Site")
        }
    }

    /// One coordinate of the spot. A spot appears once both are known.
    private func coordinate(_ path: WritableKeyPath<GeoPoint, Double>, draft: Binding<LocationDraft>) -> Binding<Double?> {
        Binding {
            draft.wrappedValue.point?[keyPath: path] ?? (path == \.latitude ? typedLatitude : typedLongitude)
        } set: { value in
            if var point = draft.wrappedValue.point {
                if let value { point[keyPath: path] = value }
                draft.wrappedValue.point = point
                return
            }
            if path == \.latitude { typedLatitude = value } else { typedLongitude = value }
            if let latitude = typedLatitude, let longitude = typedLongitude {
                draft.wrappedValue.point = GeoPoint(latitude: latitude, longitude: longitude)
            }
        }
    }

    private func save(_ draft: LocationDraft) {
        saving = true
        Task {
            do {
                let location = try await store.save(draft)
                navigation.locationDraft = nil
                navigation.locationSelection = location
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
