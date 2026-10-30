import SwiftUI

struct DevicesView: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        Table(store.devices) {
            TableColumn("Device") { device in
                Label {
                    Text(device.name)
                } icon: {
                    Circle()
                        .fill(device.active ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .width(min: 180, ideal: 240)
            TableColumn("Number") { device in
                Text(String(device.number)).monospaced()
            }
            .width(min: 110, ideal: 130)
            TableColumn("Manufacturer") { device in
                Text(store.organization(device.manufacturerID)?.name ?? "—")
            }
            TableColumn("Operator") { device in
                Text(store.organization(device.operatorID)?.name ?? "—")
            }
            TableColumn("Methods") { device in
                Text(store.actions(using: device).map(\.name).formatted(.list(type: .and)))
                    .foregroundStyle(.secondary)
            }
            TableColumn("Active") { device in
                Toggle("Active", isOn: Binding(
                    get: { device.active },
                    set: { active in store.perform { try await store.setActive(active, device: device) } }))
                .labelsHidden()
                .disabled(!store.can(.admin))
                .help(store.can(.admin) ? "Switch the device on or off" : "Needs the admin role")
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .width(60)
        }
        .navigationTitle("Devices")
    }
}
