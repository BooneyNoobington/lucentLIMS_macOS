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
    @State private var showsActionPicker = false
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

    /// The combination of actions planned most often for a matrix, as a starting point.
    private static func usualActions(for matrixID: Int, in store: LabStore) -> Set<Int> {
        Set(store.actionSets(for: matrixID).first?.actionIDs ?? [])
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
                    if actionIDs.isEmpty {
                        Text("No actions planned yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.actions.filter { actionIDs.contains($0.id) }) { action in
                        HStack {
                            ActionLabel(action: action)
                            Spacer()
                            Button("Remove \(action.name)", systemImage: "minus.circle") { actionIDs.remove(action.id) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                        }
                    }
                    HStack {
                        Button("Add Actions…", systemImage: "plus.circle") { showsActionPicker = true }
                            #if os(macOS)
                            .popover(isPresented: $showsActionPicker, arrowEdge: .bottom) {
                                ActionPicker(selection: $actionIDs, matrixID: matrixID)
                                    .environment(store)
                            }
                            #endif
                        Spacer()
                        let sets = store.actionSets(for: matrixID)
                        Menu("Plan Like…") {
                            ForEach(sets.prefix(5)) { set in
                                Button {
                                    actionIDs = Set(set.actionIDs)
                                } label: {
                                    Text(set.actionIDs.compactMap { store.action($0)?.name }.formatted(.list(type: .and)))
                                    Text("^[\(set.count) collection](inflect: true), last \(set.last.formatted(date: .abbreviated, time: .omitted))")
                                }
                            }
                        }
                        .fixedSize()
                        .disabled(sets.isEmpty)
                        .help("Plan the actions of earlier collections of this matrix")
                    }
                    .buttonStyle(.borderless)
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
            #if os(iOS)
            // A sheet on the form, not a popover on the button: it presents even while the row is out of view.
            .sheet(isPresented: $showsActionPicker) {
                ActionPicker(selection: $actionIDs, matrixID: matrixID)
                    .environment(store)
            }
            #endif
            #if DEBUG
            .task {
                // -pickActions YES opens the picker, once the sheet has settled.
                guard UserDefaults.standard.bool(forKey: "pickActions") else { return }
                try? await Task.sleep(for: .seconds(1))
                showsActionPicker = true
            }
            #endif
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

/// An action's name with the parameters it yields.
private struct ActionLabel: View {
    @Environment(LabStore.self) private var store
    let action: LabAction

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(action.name)
            Text(store.effects(of: action).compactMap { store.parameter($0.parameterID)?.name }
                .formatted(.list(type: .and)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

/// Picks actions to plan: searchable, with the ones often planned for the matrix first.
private struct ActionPicker: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Set<Int>
    let matrixID: Int
    @State private var search = ""

    var body: some View {
        let usual = store.usualActions(for: matrixID).filter { $0.active && store.action($0, matches: search) }
        let others = store.actions.filter { action in
            action.active && !usual.contains(action) && store.action(action, matches: search)
        }
        NavigationStack {
            List {
                if !usual.isEmpty {
                    Section("Often planned for \(store.matrix(matrixID)?.name ?? "this matrix")") {
                        ForEach(usual) { row($0) }
                    }
                }
                if !others.isEmpty {
                    Section(usual.isEmpty ? "Actions" : "Other actions") {
                        ForEach(others) { row($0) }
                    }
                }
                if usual.isEmpty && others.isEmpty {
                    Text("No action matches “\(search)”.")
                        .foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .top) {
                TextField("Search", text: $search, prompt: Text("Action, parameter or document"))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .navigationTitle("Add Actions")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 380, height: 460)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func row(_ action: LabAction) -> some View {
        let chosen = selection.contains(action.id)
        return Button {
            if chosen { selection.remove(action.id) } else { selection.insert(action.id) }
        } label: {
            HStack {
                ActionLabel(action: action)
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosen ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
