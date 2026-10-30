import SwiftUI

/// Analytical methods and procedures (`action` in lucentBASE).
struct MethodsView: View {
    @Environment(LabStore.self) private var store
    @State private var search = ""

    var body: some View {
        let actions = store.actions.filter { action in
            search.isEmpty || action.name.localizedStandardContains(search)
                || action.description.localizedStandardContains(search)
                || action.documentIDs.contains { store.document($0)?.name.localizedStandardContains(search) == true }
        }
        List(actions) { action in
            NavigationLink(value: Route.method(action.id)) {
                MethodRow(action: action)
            }
        }
        .searchable(text: $search, prompt: "Method, standard or document")
        .navigationTitle("Methods")
    }
}

private struct MethodRow: View {
    @Environment(LabStore.self) private var store
    let action: LabAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flask.fill")
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background((action.active ? Color.accentColor : Color.gray).gradient,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.name)
                        .font(.body.weight(.medium))
                    Text(action.active ? action.iteration.formatted(.dateTime.month(.abbreviated).year())
                                       : String(localized: "Inactive"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(action.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(store.effects(of: action).compactMap { store.parameter($0.parameterID)?.name }
                    .formatted(.list(type: .and)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

struct MethodDetailView: View {
    @Environment(LabStore.self) private var store
    let action: LabAction

    var body: some View {
        let versions = store.actions.filter { $0.name == action.name && $0.id != action.id }
        let requiredBy = store.actions.filter { other in other.dependencies.contains { $0.actionID == action.id } }

        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.name)
                        .font(.title2.weight(.semibold))
                    Text("Version of \(action.iteration.formatted(date: .long, time: .omitted))")
                        .foregroundStyle(.secondary)
                    if !action.active {
                        Label("Inactive", systemImage: "pause.circle")
                            .foregroundStyle(.orange)
                    }
                    Text(action.description)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(store.effects(of: action)) { effect in
                    EffectRow(effect: effect)
                }
            } header: {
                Text("Effects")
            } footer: {
                Text("What the action yields. Every effect becomes a value of the collections it is planned for.")
            }

            if !action.dependencies.isEmpty || !requiredBy.isEmpty || !versions.isEmpty {
                Section("Workflow") {
                    ForEach(action.dependencies, id: \.self) { dependency in
                        if let other = store.action(dependency.actionID) {
                            NavigationLink(value: Route.method(other.id)) {
                                LabeledContent {
                                    Text(other.name)
                                } label: {
                                    Text(dependency.kind == .strict ? "Requires" : "Can use")
                                    if !dependency.description.isEmpty { Text(dependency.description) }
                                }
                            }
                        }
                    }
                    ForEach(requiredBy) { other in
                        NavigationLink(value: Route.method(other.id)) {
                            LabeledContent("Required by", value: other.name)
                        }
                    }
                    ForEach(versions) { other in
                        NavigationLink(value: Route.method(other.id)) {
                            LabeledContent(other.active ? "Other version" : "Earlier version",
                                           value: other.iteration.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }
            }

            if !action.documentIDs.isEmpty {
                Section("Documents") {
                    ForEach(action.documentIDs.compactMap { store.document($0) }) { document in
                        NavigationLink(value: Route.document(document.id)) {
                            Label(document.name, systemImage: document.systemImage)
                        }
                    }
                }
            }

            if !action.deviceIDs.isEmpty {
                Section("Devices") {
                    ForEach(action.deviceIDs.compactMap { store.device($0) }) { device in
                        LabeledContent {
                            Text(device.active ? "Active" : "Inactive")
                                .foregroundStyle(device.active ? Color.green : Color.secondary)
                        } label: {
                            Text(device.name)
                            Text(String(device.number)).monospaced()
                        }
                    }
                }
            }

            Section("People") {
                ForEach(action.people, id: \.self) { assignment in
                    if let person = store.person(assignment.personID) {
                        NavigationLink(value: Route.person(person.id)) {
                            LabeledContent {
                                Text(assignment.role.capitalized)
                            } label: {
                                HStack(spacing: 8) {
                                    Avatar(person: person, size: 24)
                                    Text(person.fullName)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(action.name)
    }
}

private struct EffectRow: View {
    @Environment(LabStore.self) private var store
    let effect: Effect

    var body: some View {
        let parameter = store.parameter(effect.parameterID)
        let coefficients = store.coefficients.filter { $0.effectIDs.contains(effect.id) }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(parameter?.name ?? "—", systemImage: parameter?.valueClass.systemImage ?? "number")
                Spacer()
                Text(store.unit(parameter?.unitID)?.symbol ?? "")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let uncertainty = store.uncertaintyText(effect) {
                    Text("Uncertainty \(uncertainty)")
                }
                if let limit = store.limitPhrase(effect) {
                    Text(limit)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let calculation = effect.calculation {
                Text(calculation)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            ForEach(coefficients) { coefficient in
                Label(coefficient.description, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
