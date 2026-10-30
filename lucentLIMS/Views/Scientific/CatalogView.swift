import SwiftUI

/// Parameters, units, dimensions, matrices and collection classes.
struct CatalogView: View {
    @Environment(LabStore.self) private var store
    @State private var catalog = Catalog.parameters
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private let isCompact = false
    #endif

    enum Catalog: String, CaseIterable, Identifiable {
        case parameters, units, dimensions, matrices, classes
        var id: String { rawValue }

        var title: String {
            switch self {
            case .parameters: String(localized: "Parameters")
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
        case .parameters:
            Table(store.parameters) {
                TableColumn("Parameter") { parameter in
                    VStack(alignment: .leading) {
                        Text(parameter.name)
                        Text(parameter.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .width(min: 180, ideal: 240)
                TableColumn("Value class") { parameter in
                    Label(parameter.valueClass.title, systemImage: parameter.valueClass.systemImage)
                }
                .width(min: 100, ideal: 120)
                TableColumn("Unit") { parameter in
                    Text(store.unit(parameter.unitID)?.symbol ?? "—")
                }
                .width(min: 70, ideal: 90)
                TableColumn("Dimension") { parameter in
                    Text(store.dimension(store.unit(parameter.unitID)?.dimensionID)?.name ?? "—")
                }
                TableColumn("Limits") { parameter in
                    Text(store.thresholds.filter { $0.parameterID == parameter.id }
                        .map { "\(store.limitText($0)) \(store.document($0.documentID)?.shortName ?? "")" }
                        .joined(separator: ", "))
                }
                .width(min: 120, ideal: 200)
                TableColumn("Yielded by") { parameter in
                    Text(store.effects(of: parameter).compactMap { store.action($0.actionID) }.filter(\.active)
                        .map(\.name).formatted(.list(type: .and)))
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
            Table(store.collectionClasses.map(ClassRow.init)) {
                TableColumn("Collection class", value: \.id)
                TableColumn("Collections") { row in
                    Text("\(store.collections.filter { $0.collectionClass == row.id }.count)").monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("Matrices") { row in
                    let ids = Set(store.collections.filter { $0.collectionClass == row.id }.map(\.matrixID))
                    Text(store.matrices.filter { ids.contains($0.id) }.map(\.name).formatted(.list(type: .and)))
                }
            }
        }
    }

    /// lucentBASE's collection classes are an ENUM, so a class is just its name.
    private struct ClassRow: Identifiable {
        let id: String
    }
}
