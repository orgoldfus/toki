import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        Form {
            Picker("Microphone", selection: $model.selectedInputDeviceID) {
                Text("Built-in Microphone").tag("input-built-in")
                Text("Studio USB").tag("input-studio")
            }

            Picker("Output Device", selection: $model.selectedOutputDeviceID) {
                Text("System Default").tag("output-system")
                Text("AirPods Pro").tag("output-airpods")
            }

            HStack {
                Text("PTT Shortcut")
                Spacer()
                Text(model.pushToTalkShortcutLabel)
                    .foregroundStyle(.secondary)
            }

            Toggle("Launch At Login", isOn: $model.launchAtLogin)
            Toggle("Diagnostics Opt-In", isOn: $model.diagnosticsOptIn)

            Text("Global shortcut capture stays local in this slice. Audio transport and device activation are intentionally not implemented here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(20)
        .onChange(of: model.selectedInputDeviceID) { _, _ in model.saveSettings() }
        .onChange(of: model.selectedOutputDeviceID) { _, _ in model.saveSettings() }
        .onChange(of: model.launchAtLogin) { _, _ in model.saveSettings() }
        .onChange(of: model.diagnosticsOptIn) { _, _ in model.saveSettings() }
    }
}
