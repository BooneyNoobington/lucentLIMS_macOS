import SwiftUI

/// Registers a collection, like lucentAndShiny's "Add Collection" dialog.
struct NewCollectionSheet: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    enum Relation: Hashable { case spot, site }

    @State private var matrixID: Int
    @State private var classID: Int
    @State private var relation = Relation.spot
    @State private var spotID: Int
    @State private var siteID: Int
    @State private var sampledAt = Date.now
    @State private var samplerID: Int
    @State private var saving = false
    @State private var error: String?

    init(store: LabStore) {
        _matrixID = State(initialValue: store.matrices.first?.id ?? 0)
        _classID = State(initialValue: store.collectionClasses.first?.id ?? 0)
        _spotID = State(initialValue: store.spots.first?.id ?? 0)
        _siteID = State(initialValue: store.sites.first?.id ?? 0)
        _samplerID = State(initialValue: store.currentUser.id)
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
                    Picker("Collection class", selection: $classID) {
                        ForEach(store.collectionClasses) { Text($0.name).tag($0.id) }
                    }
                    DatePicker("Sampled at", selection: $sampledAt)
                    Picker("Sampled by", selection: $samplerID) {
                        ForEach(store.people) { Text($0.fullName).tag($0.id) }
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

                Section("Planned methods") {
                    ForEach(store.actions(forClass: classID)) { action in
                        LabeledContent {
                            Text("^[\(store.actionVariables(of: action).count) value](inflect: true)")
                        } label: {
                            Label(action.name, systemImage: "flask")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Register") {
                        saving = true
                        Task {
                            do {
                                let collection = try await store.registerCollection(
                                    matrixID: matrixID, classID: classID,
                                    spotID: relation == .spot ? spotID : nil,
                                    siteID: relation == .site ? siteID : nil,
                                    sampledAt: sampledAt, sampledByID: samplerID)
                                navigation.open(collection: collection.id)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving || !store.can(.sampler))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }
}
