import SwiftUI
import MapKit

/// Everything about one collection: where and when it was sampled, its values and actions.
/// A value is the slot for one effect of a planned action; its raw values are the readings.
struct CollectionDetailView: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    let collection: LabCollection

    @State private var tab = Tab.values

    enum Tab: Hashable { case values, actions, sampling }

    var body: some View {
        let status = store.status(of: collection)
        let progress = store.progress(of: collection)
        let actions = store.plannedActions(of: collection)

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
                        Text("\(matrix?.name ?? "—") · \(collection.collectionClass)")
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
                        ForEach(store.values(of: collection.id, for: action)) { value in
                            if let effect = store.effect(value.effectID) {
                                let raws = store.rawValues(of: value)
                                if raws.isEmpty {
                                    PendingValueRow(value: value, effect: effect)
                                } else {
                                    ForEach(Array(raws.enumerated()), id: \.element.id) { index, raw in
                                        RawValueRow(raw: raw, effect: effect, repetition: index + 1)
                                    }
                                }
                            }
                        }
                    }
                }
                if status == .inReview {
                    Section {
                        Button("Accept All Raw Values", systemImage: "checkmark.seal.fill") {
                            store.perform { try await store.acceptAll(in: [collection.id]) }
                        }
                        .disabled(!store.can(.reviewer))
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
                    LabeledContent("Collection class", value: collection.collectionClass)
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
                if let spot = store.spot(id), let point = spot.point {
                    Marker(spot.name, systemImage: store.primaryMatrix(at: location)?.systemImage ?? "mappin",
                           coordinate: point.coordinate)
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
            MKCoordinateRegion(center: store.spot(id)?.point?.coordinate ?? LocationsView.karlsruhe.center,
                               latitudinalMeters: 700, longitudinalMeters: 700)
        case .site(let id):
            store.site(id).map { LocationsView.region(for: $0) } ?? LocationsView.karlsruhe
        }
    }
}

/// A reading of a value. Readings after the first are repetitions.
private struct RawValueRow: View {
    @Environment(LabStore.self) private var store
    let raw: RawValue
    let effect: Effect
    let repetition: Int

    var body: some View {
        let exceeds = store.exceeds(raw, of: effect)
        let ownReading = raw.personID == store.currentUser.id
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(store.parameter(effect.parameterID)?.name ?? "—")
                    if repetition > 1 {
                        Text("Repetition \(repetition)")
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
            Text(store.format(raw))
                .monospacedDigit()
                .fontWeight(exceeds ? .semibold : .regular)
                .foregroundStyle(exceeds ? .red : .primary)
            Button {
                store.perform { try await store.setAccepted(!raw.accepted, rawValue: raw) }
            } label: {
                Image(systemName: raw.accepted ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(raw.accepted ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .disabled(!store.can(.reviewer) || (ownReading && !raw.accepted))
            .help(!store.can(.reviewer) ? "Needs the reviewer role"
                  : raw.accepted ? "Accepted. Click to withdraw."
                  : ownReading ? "You measured this, so someone else has to accept it" : "Accept this raw value")
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let uncertainty = store.uncertaintyText(effect) { parts.append(uncertainty) }
        if let limit = store.limitPhrase(effect) { parts.append(limit) }
        // A sampling time is its own t; showing it twice says nothing.
        if let t = raw.t, raw.reading != .datetime(t) { parts.append(t.formatted(date: .numeric, time: .shortened)) }
        if let person = store.person(raw.personID) { parts.append(person.linuxUser) }
        return parts.joined(separator: " · ")
    }
}

/// A value without readings yet, with a field to record the first.
private struct PendingValueRow: View {
    @Environment(LabStore.self) private var store
    let value: LabValue
    let effect: Effect
    @State private var text = ""
    @State private var date = Date.now

    var body: some View {
        let parameter = store.parameter(effect.parameterID)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(parameter?.name ?? "—")
                Text("Pending")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            if !store.can(.analyst) {
                Text("—").foregroundStyle(.tertiary).help("Recording raw values needs the analyst role")
            } else {
            switch parameter?.valueClass ?? .decimal {
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
                Text(store.unit(parameter?.unitID)?.symbol ?? "")
                    .foregroundStyle(.secondary)
            case .text:
                TextField("Value", text: $text, prompt: Text("Value"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .onSubmit { if !text.isEmpty { record(.text(text)) } }
            case .datetime:
                DatePicker("Value", selection: $date)
                    .labelsHidden()
                Button("Record") { record(.datetime(date)) }
            }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func record(_ reading: Reading) {
        store.perform { try await store.record(reading, for: value) }
    }
}

private struct ActionProgressRow: View {
    @Environment(LabStore.self) private var store
    let action: LabAction
    let collection: LabCollection

    var body: some View {
        let values = store.values(of: collection.id, for: action)
        let measured = values.filter { !store.rawValues(of: $0).isEmpty }.count
        let done = measured == values.count

        Section {
            NavigationLink(value: Route.method(action.id)) {
                HStack(spacing: 12) {
                    Image(systemName: done ? "checkmark.circle.fill" : measured > 0 ? "circle.lefthalf.filled" : "circle")
                        .font(.title3)
                        .foregroundStyle(done ? Color.green : measured > 0 ? Color.orange : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.name)
                        Text(summary(measured: measured, planned: values.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let device = action.deviceIDs.compactMap({ store.device($0) }).first(where: \.active) {
                LabeledContent("Device", value: device.name)
            }
            ForEach(action.people, id: \.self) { assignment in
                LabeledContent(assignment.role.capitalized, value: store.person(assignment.personID)?.fullName ?? "—")
            }
            let required = action.dependencies.filter { $0.kind == .strict }.compactMap { store.action($0.actionID)?.name }
            if !required.isEmpty {
                LabeledContent("Requires", value: required.formatted(.list(type: .and)))
            }
        }
    }

    private func summary(measured: Int, planned: Int) -> String {
        let progress = String(localized: "\(measured) of \(planned) values")
        guard let sop = action.documentIDs.compactMap({ store.document($0) }).first else { return progress }
        return "\(sop.name) · \(progress)"
    }
}
