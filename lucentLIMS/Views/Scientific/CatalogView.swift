import SwiftUI

/// Variables, units, dimensions, matrices and collection classes.
struct CatalogView: View {
    @Environment(LabStore.self) private var store
    @State private var catalog = Catalog.variables
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private let isCompact = false
    #endif

    enum Catalog: String, CaseIterable, Identifiable {
        case variables, units, dimensions, matrices, classes
        var id: String { rawValue }

        var title: String {
            switch self {
            case .variables: String(localized: "Variables")
            case .units: String(localized: "Units")
            case .dimensions: String(localized: "Dimensions")
            case .matrices: String(localized: "Matrices")
            case .classes: String(localized: "Classes")
            }
        }
    }

    var body: some View {
        content
            .navigationTitle(catalog.title)
            .toolbar {
                ToolbarItem(placement: isCompact ? .primaryAction : .principal) {
                    let picker = Picker("Catalog", selection: $catalog) {
                        ForEach(Catalog.allCases) { Text($0.title).tag($0) }
                    }
                    if isCompact {
                        picker.pickerStyle(.menu)
                    } else {
                        picker.pickerStyle(.segmented).fixedSize()
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch catalog {
        case .variables:
            Table(store.variables) {
                TableColumn("Variable") { variable in
                    VStack(alignment: .leading) {
                        Text(variable.name)
                        Text(variable.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .width(min: 180, ideal: 240)
                TableColumn("Value class") { variable in
                    Label(variable.valueClass.title, systemImage: variable.valueClass.systemImage)
                }
                .width(min: 100, ideal: 120)
                TableColumn("Dimension") { variable in
                    Text(store.dimension(variable.dimensionID)?.name ?? "—")
                }
                TableColumn("Unit") { variable in
                    Text(Set(store.actionVariables(of: variable).compactMap { store.unit($0.unitID)?.symbol })
                        .sorted().joined(separator: ", "))
                }
                .width(min: 70, ideal: 90)
                TableColumn("Limit") { variable in
                    Text(store.actionVariables(of: variable).compactMap { store.limitText($0) }.joined(separator: ", "))
                }
                .width(min: 90, ideal: 110)
                TableColumn("Measured by") { variable in
                    Text(store.actionVariables(of: variable).compactMap { store.action($0.actionID)?.name }
                        .formatted(.list(type: .and)))
                }
            }
        case .units:
            Table(store.units) {
                TableColumn("Unit", value: \.name)
                TableColumn("Symbol") { unit in Text(unit.symbol.isEmpty ? "—" : unit.symbol) }
                    .width(min: 80, ideal: 100)
                TableColumn("Notations") { unit in
                    Text(unit.notations.joined(separator: "  ·  ")).foregroundStyle(.secondary)
                }
                TableColumn("Dimension") { unit in Text(store.dimension(unit.dimensionID)?.name ?? "—") }
            }
        case .dimensions:
            Table(store.dimensions) {
                TableColumn("Dimension", value: \.name)
                TableColumn("Description", value: \.description)
                TableColumn("Units") { dimension in
                    Text(store.units.filter { $0.dimensionID == dimension.id }.map(\.name).formatted(.list(type: .and)))
                }
            }
        case .matrices:
            Table(store.matrices) {
                TableColumn("Matrix") { matrix in MatrixLabel(matrix: matrix) }
                TableColumn("Description", value: \.description)
                TableColumn("Collections") { matrix in
                    Text("\(store.collections.filter { $0.matrixID == matrix.id }.count)").monospacedDigit()
                }
                .width(min: 80, ideal: 100)
            }
        case .classes:
            Table(store.collectionClasses) {
                TableColumn("Collection class", value: \.name)
                TableColumn("Description", value: \.description)
                TableColumn("Planned methods") { collectionClass in
                    Text(store.actions(forClass: collectionClass.id).map(\.name).formatted(.list(type: .and)))
                }
            }
        }
    }
}
