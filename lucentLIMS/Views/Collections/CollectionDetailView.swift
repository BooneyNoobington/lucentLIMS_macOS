import SwiftUI
import MapKit

/// Everything about one collection: where and when it was sampled, its values and actions.
struct CollectionDetailView: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    let collection: LabCollection

    @State private var tab = Tab.values

    enum Tab: Hashable { case values, actions, sampling }

    var body: some View {
        let status = store.status(of: collection)
        let progress = store.progress(of: collection)
        let actions = store.actions(forClass: collection.classID)

        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        IdentifierView(identifier: collection.name)
                            .font(.title2)
                        Spacer()
                        StatusBadge(status: status)
                    }
                    let matrix = store.matrix(collection.matrixID)
                    Label {
                        Text("\(matrix?.name ?? "—") · \(store.collectionClass(collection.classID)?.name ?? "—")")
                    } icon: {
                        Image(systemName: matrix?.systemImage ?? "questionmark")
                            .foregroundStyle(matrix?.tint ?? .gray)
                    }
                    .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ProgressView(value: Double(progress.measured), total: Double(max(progress.planned, 1)))
                            .tint(status.tint)
                        Text("\(progress.measured) of \(progress.planned) values")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Show", selection: $tab) {
                    Text("Values").tag(Tab.values)
                    Text("Actions").tag(Tab.actions)
                    Text("Sampling").tag(Tab.sampling)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch tab {
            case .values:
                ForEach(actions) { action in
                    Section(action.name) {
                        ForEach(store.actionVariables(of: action)) { actionVariable in
                            let values = store.values(of: collection.id, for: actionVariable)
                            if values.isEmpty {
                                PendingValueRow(collectionID: collection.id, actionVariable: actionVariable)
                            } else {
                                ForEach(values) { value in
                                    ValueRow(value: value, actionVariable: actionVariable)
                                }
                            }
                        }
                    }
                }
                if status == .inReview {
                    Section {
                        Button("Accept All Values", systemImage: "checkmark.seal.fill") {
                            withAnimation { store.acceptAll(in: [collection.id]) }
                        }
                    } footer: {
                        Text("Approval follows the four-eyes principle of SOP-009.")
                    }
                }
            case .actions:
                ForEach(actions) { action in
                    ActionProgressRow(action: action, collection: collection)
                }
            case .sampling:
                if let location = store.location(of: collection) {
                    Section {
                        LocationMap(location: location)
                            .frame(height: 170)
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section("Sampling") {
                    LabeledContent("Sampled", value: collection.sampledAt.formatted(date: .abbreviated, time: .shortened))
                    if let sampler = store.person(collection.sampledByID) {
                        NavigationLink(value: Route.person(sampler.id)) {
                            LabeledContent("By") {
                                HStack(spacing: 6) {
                                    Avatar(person: sampler, size: 20)
                                    Text(sampler.fullName)
                                }
                            }
                        }
                    }
                    if let location = store.location(of: collection) {
                        LabeledContent("Location") {
                            Button(store.locationName(of: collection)) { navigation.open(location: location) }
                                .buttonStyle(.borderless)
                        }
                    }
                    if let address = store.site(collection.siteID ?? store.spot(collection.spotID)?.siteID)?.address {
                        LabeledContent("Address") {
                            VStack(alignment: .trailing) {
                                Text(address.line1)
                                Text(address.line2)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A map with one spot or site, not interactive.
struct LocationMap: View {
    @Environment(LabStore.self) private var store
    let location: LocationRef

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            switch location {
            case .spot(let id):
                if let spot = store.spot(id) {
                    Marker(spot.name, systemImage: store.primaryMatrix(at: location)?.systemImage ?? "mappin",
                           coordinate: spot.point.coordinate)
                        .tint(store.primaryMatrix(at: location)?.tint ?? .accentColor)
                }
            case .site(let id):
                if let site = store.site(id) {
                    MapPolygon(coordinates: site.border.map(\.coordinate))
                        .foregroundStyle(Color.accentColor.opacity(0.2))
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .id(location)
    }

    private var region: MKCoordinateRegion {
        switch location {
        case .spot(let id):
            MKCoordinateRegion(center: store.spot(id)?.point.coordinate ?? LocationsView.karlsruhe.center,
                               latitudinalMeters: 700, longitudinalMeters: 700)
        case .site(let id):
            store.site(id).map { LocationsView.region(for: $0) } ?? LocationsView.karlsruhe
        }
    }
}

private struct ValueRow: View {
    @Environment(LabStore.self) private var store
    let value: LabValue
    let actionVariable: ActionVariable

    var body: some View {
        let exceeds = actionVariable.exceeds(value.reading)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(store.variable(actionVariable.variableID)?.name ?? "—")
                    if value.repetition > 1 {
                        Text("Repetition \(value.repetition)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if exceeds {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("Outside the limit")
            }
            Text(store.format(value.reading, actionVariable))
                .monospacedDigit()
                .fontWeight(exceeds ? .semibold : .regular)
                .foregroundStyle(exceeds ? .red : .primary)
            Button {
                withAnimation { store.setAccepted(!value.accepted, valueID: value.id, in: value.collectionID) }
            } label: {
                Image(systemName: value.accepted ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(value.accepted ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(value.accepted ? "Accepted. Click to withdraw." : "Accept this value")
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let uncertainty = store.uncertaintyText(actionVariable) { parts.append(uncertainty) }
        if let limit = store.limitPhrase(actionVariable) { parts.append(limit) }
        parts.append(value.measuredAt.formatted(date: .numeric, time: .shortened))
        if let person = store.person(value.personID) { parts.append(person.unixAccount) }
        return parts.joined(separator: " · ")
    }
}

/// A value still to be measured, with a field to record it.
private struct PendingValueRow: View {
    @Environment(LabStore.self) private var store
    let collectionID: Int
    let actionVariable: ActionVariable
    @State private var text = ""

    var body: some View {
        let variable = store.variable(actionVariable.variableID)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(variable?.name ?? "—")
                Text("Pending")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            switch variable?.valueClass ?? .decimal {
            case .boolean:
                Button("No") { record(.boolean(false)) }
                Button("Yes") { record(.boolean(true)) }
            case .decimal:
                TextField("Value", text: $text, prompt: Text("Value"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .onSubmit {
                        if let number = Double(text.replacingOccurrences(of: ",", with: ".")) {
                            record(.decimal(number))
                        }
                    }
                Text(store.unit(actionVariable.unitID)?.symbol ?? "")
                    .foregroundStyle(.secondary)
            case .text, .datetime:
                TextField("Value", text: $text, prompt: Text("Value"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .onSubmit { if !text.isEmpty { record(.text(text)) } }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func record(_ reading: Reading) {
        withAnimation { store.record(reading, for: actionVariable, in: collectionID) }
    }
}

private struct ActionProgressRow: View {
    @Environment(LabStore.self) private var store
    let action: LabAction
    let collection: LabCollection

    var body: some View {
        let variables = store.actionVariables(of: action)
        let measured = variables.filter { !store.values(of: collection.id, for: $0).isEmpty }.count
        let done = measured == variables.count

        Section {
            NavigationLink(value: Route.method(action.id)) {
                HStack(spacing: 12) {
                    Image(systemName: done ? "checkmark.circle.fill" : measured > 0 ? "circle.lefthalf.filled" : "circle")
                        .font(.title3)
                        .foregroundStyle(done ? Color.green : measured > 0 ? Color.orange : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.name)
                        Text("\(action.standard) · \(measured) of \(variables.count) values")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let device = action.deviceIDs.compactMap({ store.device($0) }).first(where: \.active) {
                LabeledContent("Device", value: device.name)
            }
            ForEach(action.people, id: \.self) { assignment in
                LabeledContent(assignment.role, value: store.person(assignment.personID)?.fullName ?? "—")
            }
            if !action.dependsOn.isEmpty {
                LabeledContent("Requires",
                               value: action.dependsOn.compactMap { store.action($0)?.name }.formatted(.list(type: .and)))
            }
        }
    }
}
