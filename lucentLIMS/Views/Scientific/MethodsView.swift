import SwiftUI

/// Analytical methods and procedures (`action` in lucentBASE).
struct MethodsView: View {
    @Environment(LabStore.self) private var store
    @State private var search = ""

    var body: some View {
        let actions = store.actions.filter {
            search.isEmpty || $0.name.localizedStandardContains(search) || $0.standard.localizedStandardContains(search)
        }
        List(actions) { action in
            NavigationLink(value: Route.method(action.id)) {
                MethodRow(action: action)
            }
        }
        .searchable(text: $search, prompt: "Method or standard")
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
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.name)
                        .font(.body.weight(.medium))
                    Text("Rev. \(action.iteration)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(action.standard)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.actionVariables(of: action).compactMap { store.variable($0.variableID)?.name }
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
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.name)
                        .font(.title2.weight(.semibold))
                    Text("\(action.standard) · Revision \(action.iteration)")
                        .foregroundStyle(.secondary)
                    Text(action.description)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

            Section("Measured variables") {
                ForEach(store.actionVariables(of: action)) { actionVariable in
                    VariableRow(actionVariable: actionVariable)
                }
            }

            Section("Workflow") {
                ForEach(action.dependsOn, id: \.self) { id in
                    if let other = store.action(id) {
                        NavigationLink(value: Route.method(id)) {
                            LabeledContent("Requires", value: other.name)
                        }
                    }
                }
                ForEach(action.implies, id: \.self) { id in
                    if let other = store.action(id) {
                        NavigationLink(value: Route.method(id)) {
                            LabeledContent("Implies", value: other.name)
                        }
                    }
                }
                LabeledContent("Collection classes",
                               value: store.classes(using: action).map(\.name).formatted(.list(type: .and)))
            }

            if let sop = store.sop(action.sopID) {
                Section("SOP") {
                    NavigationLink(value: Route.sop(sop.id)) {
                        Label(sop.name, systemImage: "doc.text")
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
                            Text(device.number).monospaced()
                        }
                    }
                }
            }

            Section("People") {
                ForEach(action.people, id: \.self) { assignment in
                    if let person = store.person(assignment.personID) {
                        NavigationLink(value: Route.person(person.id)) {
                            LabeledContent {
                                Text(assignment.role)
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

private struct VariableRow: View {
    @Environment(LabStore.self) private var store
    let actionVariable: ActionVariable

    var body: some View {
        let variable = store.variable(actionVariable.variableID)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(variable?.name ?? "—", systemImage: variable?.valueClass.systemImage ?? "number")
                Spacer()
                Text(store.unit(actionVariable.unitID)?.symbol ?? "")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let uncertainty = store.uncertaintyText(actionVariable) {
                    Text("Uncertainty \(uncertainty)")
                }
                if let limit = store.limitPhrase(actionVariable) {
                    Text(limit)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let calculation = actionVariable.calculation {
                Text(calculation)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 2)
    }
}
