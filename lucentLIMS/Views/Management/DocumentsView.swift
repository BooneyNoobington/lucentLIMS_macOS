import SwiftUI

/// SOPs, standards, regulations, manuals: lucentBASE's `link`. Actions refer to them, and
/// their thresholds are the limits of the actions' raw values.
struct DocumentsView: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        List(store.documents) { document in
            NavigationLink(value: Route.document(document.id)) {
                HStack(spacing: 12) {
                    Image(systemName: document.systemImage)
                        .font(.title3)
                        .foregroundStyle(document.accepted ? Color.accentColor : Color.orange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.name)
                            .font(.body.weight(.medium))
                        Text(subtitle(document))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !document.accepted {
                        Text("Not accepted")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Documents")
    }

    private func subtitle(_ document: Document) -> String {
        let methods = store.actions(referringTo: document).filter(\.active).map(\.name)
        let thresholds = store.thresholds.filter { $0.documentID == document.id }.count
        var parts: [String] = []
        if thresholds > 0 {
            parts.append(String(AttributedString(localized: "^[\(thresholds) limit](inflect: true)").characters))
        }
        if !methods.isEmpty { parts.append(methods.formatted(.list(type: .and))) }
        return parts.isEmpty ? (document.url?.host() ?? document.filePath ?? "") : parts.joined(separator: " · ")
    }
}

struct DocumentDetailView: View {
    @Environment(LabStore.self) private var store
    let document: Document

    var body: some View {
        let thresholds = store.thresholds.filter { $0.documentID == document.id }
        let methods = store.actions(referringTo: document)

        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.name)
                        .font(.title2.weight(.semibold))
                    Label(document.accepted ? "Accepted" : "Not accepted",
                          systemImage: document.accepted ? "checkmark.seal.fill" : "seal")
                        .foregroundStyle(document.accepted ? Color.green : Color.orange)
                }
                .padding(.vertical, 4)
            }

            Section("Location") {
                if let url = document.url {
                    LabeledContent("Address") {
                        Link(url.absoluteString, destination: url)
                            .font(.callout.monospaced())
                    }
                }
                if let path = document.filePath {
                    LabeledContent("File") {
                        Text(path)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
                LabeledContent("SHA-256") {
                    Text("\(document.sha256.prefix(16))…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .help(document.sha256)
                }
            }

            if !thresholds.isEmpty {
                Section {
                    ForEach(thresholds) { threshold in
                        LabeledContent {
                            Text(store.limitText(threshold))
                                .monospacedDigit()
                        } label: {
                            Text(store.parameter(threshold.parameterID)?.name ?? "—")
                            if !threshold.description.isEmpty { Text(threshold.description) }
                        }
                    }
                } header: {
                    Text("Limits")
                } footer: {
                    Text("They apply to the raw values of every action that refers to this document.")
                }
            }

            if !methods.isEmpty {
                Section("Methods") {
                    ForEach(methods) { action in
                        NavigationLink(value: Route.method(action.id)) {
                            LabeledContent(action.name,
                                           value: action.active ? action.iteration.formatted(date: .abbreviated, time: .omitted)
                                                                : String(localized: "Inactive"))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(document.name)
    }
}
