import SwiftUI

/// Registers a collection, like lucentAndShiny's "Add Collection" dialog. Every effect of the
/// planned actions becomes one of its values; the sampling time is recorded as a raw value.
struct NewCollectionSheet: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    enum Relation: Hashable { case spot, site }

    @State private var matrixID: Int
    @State private var collectionClass: String
    @State private var relation = Relation.spot
    @State private var spotID: Int
    @State private var siteID: Int
    @State private var actionIDs: Set<Int>
    @State private var sampledAt = Date.now
    @State private var saving = false
    @State private var error: String?

    init(store: LabStore) {
        let matrixID = store.matrices.first?.id ?? 0
        _matrixID = State(initialValue: matrixID)
        _collectionClass = State(initialValue: store.collectionClasses.first ?? "")
        _spotID = State(initialValue: store.spots.first?.id ?? 0)
        _siteID = State(initialValue: store.sites.first?.id ?? 0)
        _actionIDs = State(initialValue: Self.usualActions(for: matrixID, in: store))
    }

    /// The actions planned for the latest collection of a matrix, as a starting point.
    private static func usualActions(for matrixID: Int, in store: LabStore) -> Set<Int> {
        guard let latest = store.collections.filter({ $0.matrixID == matrixID }).max(by: { $0.sampledAt < $1.sampledAt })
        else { return [] }
        return Set(store.plannedActions(of: latest).filter(\.active).map(\.id))
    }

    private var plansSamplingTime: Bool {
        store.effects.contains { actionIDs.contains($0.actionID) && $0.parameterID == store.samplingTimeParameterID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Next identifier") {
                        IdentifierView(identifier: store.nextIdentifier)
                            .font(.title3)
                    }
                } footer: {
                    if store.isDemo {
                        Text("Mixed-radix numbering from las.yaml. Consecutive identifiers differ in the last segment, so they are hard to mix up.")
                    } else {
                        Text("The server assigns the identifier when you register; this is the one it will most likely give.")
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Sample") {
                    Picker("Matrix", selection: $matrixID) {
                        ForEach(store.matrices) { matrix in
                            Label(matrix.name, systemImage: matrix.systemImage).tag(matrix.id)
                        }
                    }
                    Picker("Collection class", selection: $collectionClass) {
                        ForEach(store.collectionClasses, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Relate collection to") {
                    Picker("Relate to", selection: $relation) {
                        Text("Spot").tag(Relation.spot)
                        Text("Site").tag(Relation.site)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch relation {
                    case .spot:
                        Picker("Spot", selection: $spotID) {
                            ForEach(store.spots) { Text($0.name).tag($0.id) }
                        }
                    case .site:
                        Picker("Site", selection: $siteID) {
                            ForEach(store.sites) { Text($0.name).tag($0.id) }
                        }
                    }
                }

                Section {
                    ForEach(store.actions.filter(\.active)) { action in
                        Toggle(isOn: Binding(
                            get: { actionIDs.contains(action.id) },
                            set: { if $0 { actionIDs.insert(action.id) } else { actionIDs.remove(action.id) } })
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.name)
                                Text(store.effects(of: action).compactMap { store.parameter($0.parameterID)?.name }
                                    .formatted(.list(type: .and)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Planned actions")
                } footer: {
                    let count = store.effects.filter { actionIDs.contains($0.actionID) }.count
                    Text("^[\(count) value](inflect: true) to measure")
                }

                Section {
                    if plansSamplingTime {
                        DatePicker("Sampled at", selection: $sampledAt)
                    }
                } header: {
                    Text("Sampling time")
                } footer: {
                    let name = store.parameter(store.samplingTimeParameterID)?.name ?? String(localized: "sampling time")
                    if plansSamplingTime {
                        Text("Recorded as the raw value of “\(name)”.")
                    } else {
                        Text("None of the planned actions yields “\(name)”, so the registration time stands in for it.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Collection")
            .onChange(of: matrixID) { _, matrixID in
                actionIDs = Self.usualActions(for: matrixID, in: store)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Register") {
                        saving = true
                        Task {
                            do {
                                let collection = try await store.registerCollection(NewCollection(
                                    matrixID: matrixID, collectionClass: collectionClass,
                                    spotID: relation == .spot ? spotID : nil,
                                    siteID: relation == .site ? siteID : nil,
                                    actionIDs: store.actions.map(\.id).filter(actionIDs.contains),
                                    sampledAt: plansSamplingTime ? sampledAt : nil))
                                navigation.open(collection: collection.id)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving || !store.can(.sampler) || collectionClass.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }
}
