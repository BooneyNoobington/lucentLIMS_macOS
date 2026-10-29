import SwiftUI

struct CollectionsView: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @State private var sortOrder = [KeyPathComparator(\CollectionRow.sequence, order: .reverse)]
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private let isCompact = false
    #endif

    private var rows: [CollectionRow] {
        let search = navigation.collectionSearch.trimmingCharacters(in: .whitespaces)
        return store.rows()
            .filter { row in
                guard let status = navigation.collectionStatusFilter else { return true }
                return row.status == status
            }
            .filter { row in
                search.isEmpty || [row.name, row.matrix, row.collectionClass, row.location, row.sampler]
                    .contains { $0.localizedStandardContains(search) }
            }
            .sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var navigation = navigation
        let rows = rows

        Table(rows, selection: $navigation.collectionSelection, sortOrder: $sortOrder) {
            TableColumn("Collection", value: \.sequence) { row in
                if isCompact {
                    // A compact table shows only its first column, so it carries the essentials.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            IdentifierView(identifier: row.name)
                            Spacer()
                            StatusBadge(status: row.status)
                        }
                        HStack(spacing: 6) {
                            MatrixLabel(matrix: store.matrix(row.matrixID))
                            Text("·")
                            Text(row.location)
                            if row.exceedances > 0 {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(row.sampledAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                } else {
                    IdentifierView(identifier: row.name)
                }
            }
            .width(min: 150, ideal: 170)
            TableColumn("Matrix", value: \.matrix) { row in
                MatrixLabel(matrix: store.matrix(row.matrixID))
            }
            .width(min: 110, ideal: 130)
            TableColumn("Class", value: \.collectionClass)
                .width(min: 110, ideal: 170)
            TableColumn("Location", value: \.location) { row in
                Label(row.location, systemImage: row.isSite ? "square.dashed" : "mappin")
            }
            .width(min: 140, ideal: 190)
            TableColumn("Sampled", value: \.sampledAt) { row in
                Text(row.sampledAt, format: .dateTime.day().month().year().hour().minute())
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 140)
            TableColumn("Progress", value: \.progress) { row in
                HStack(spacing: 8) {
                    ProgressView(value: row.progress)
                        .tint(row.status.tint)
                        .frame(width: 60)
                    Text("\(row.measured)/\(row.planned)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 110)
            TableColumn("Status", value: \.status) { row in
                HStack(spacing: 6) {
                    StatusBadge(status: row.status)
                    if row.exceedances > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .help("^[\(row.exceedances) value](inflect: true) outside the limits")
                    }
                }
            }
            .width(min: 120, ideal: 140)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            Button("Accept All Values", systemImage: "checkmark.seal") { store.acceptAll(in: ids) }
                .disabled(ids.isEmpty)
            if let id = ids.first, ids.count == 1, let collection = store.collection(id),
               let location = store.location(of: collection) {
                Button("Show on Map", systemImage: "map") { navigation.open(location: location) }
            }
        } primaryAction: { ids in
            navigation.collectionSelection = ids
            navigation.showsCollectionInspector = true
        }
        .searchable(text: $navigation.collectionSearch, prompt: "Identifier, matrix, location, sampler")
        .navigationTitle("Collections")
        #if os(macOS)
        .navigationSubtitle("\(rows.count) of \(store.collections.count)")
        #endif
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Status", selection: $navigation.collectionStatusFilter) {
                        Text("All").tag(CollectionStatus?.none)
                        Divider()
                        ForEach(CollectionStatus.allCases) { status in
                            Label(status.title, systemImage: status.systemImage).tag(Optional(status))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Filter", systemImage: navigation.collectionStatusFilter == nil
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem {
                Button("New Collection", systemImage: "plus") { navigation.presentNewCollection() }
            }
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.trailing") {
                    navigation.showsCollectionInspector.toggle()
                }
            }
        }
        .inspector(isPresented: $navigation.showsCollectionInspector) {
            CollectionInspector(selection: navigation.collectionSelection)
                .inspectorColumnWidth(min: 340, ideal: 420, max: 600)
        }
    }
}

private struct CollectionInspector: View {
    @Environment(LabStore.self) private var store
    let selection: Set<Int>

    var body: some View {
        if selection.count == 1, let collection = store.collection(selection.first) {
            CollectionDetailView(collection: collection)
                .id(collection.id)
        } else if selection.count > 1 {
            let inReview = selection.compactMap { store.collection($0) }.filter { store.status(of: $0) == .inReview }
            ContentUnavailableView {
                Label("\(selection.count) Collections", systemImage: "testtube.2")
            } description: {
                Text("\(inReview.count) of them are waiting for review.")
            } actions: {
                Button("Accept All Values") { store.acceptAll(in: selection) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView("No Collection Selected", systemImage: "testtube.2",
                                   description: Text("Select a collection to see its values and actions."))
        }
    }
}
