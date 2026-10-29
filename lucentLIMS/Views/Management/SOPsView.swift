import SwiftUI

/// Standard operating procedures with their documents (`sop`, `link`).
struct SOPsView: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        List(store.sops) { sop in
            NavigationLink(value: Route.sop(sop.id)) {
                HStack(spacing: 12) {
                    Image(systemName: sop.active ? "doc.text.fill" : "doc.badge.ellipsis")
                        .font(.title3)
                        .foregroundStyle(sop.active ? Color.accentColor : Color.orange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sop.name)
                            .font(.body.weight(.medium))
                        Text(subtitle(sop))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !sop.active {
                        Text("Draft")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("SOPs")
    }

    private func subtitle(_ sop: SOP) -> String {
        let methods = store.actions(following: sop).map(\.name)
        let documents = String(AttributedString(localized: "^[\(sop.documents.count) document](inflect: true)").characters)
        return methods.isEmpty ? documents : "\(documents) · \(methods.formatted(.list(type: .and)))"
    }
}

struct SOPDetailView: View {
    @Environment(LabStore.self) private var store
    let sop: SOP

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sop.name)
                        .font(.title2.weight(.semibold))
                    Label(sop.active ? "Active" : "Draft", systemImage: sop.active ? "checkmark.circle.fill" : "pencil.circle")
                        .foregroundStyle(sop.active ? Color.green : Color.orange)
                }
                .padding(.vertical, 4)
            }

            Section("Documents") {
                ForEach(sop.documents) { document in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: document.url != nil ? "link" : "doc.richtext")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(document.name)
                            Text(document.url?.absoluteString ?? document.filePath ?? "")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text("SHA-256 \(document.sha256.prefix(16))…")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .help(document.sha256)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: document.accepted ? "checkmark.seal.fill" : "seal")
                            Text(document.accepted ? "Accepted" : "Not accepted")
                        }
                        .font(.caption)
                            .foregroundStyle(document.accepted ? Color.green : Color.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("People") {
                ForEach(sop.people, id: \.self) { assignment in
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

            let methods = store.actions(following: sop)
            if !methods.isEmpty {
                Section("Methods") {
                    ForEach(methods) { action in
                        NavigationLink(value: Route.method(action.id)) {
                            LabeledContent(action.name, value: action.standard)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(sop.name)
    }
}
