import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        Form {
            Picker("Microphone", selection: $model.selectedInputDeviceID) {
                ForEach(model.availableInputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }

            Picker("Output Device", selection: $model.selectedOutputDeviceID) {
                ForEach(model.availableOutputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }

            if let warning = model.audioDeviceWarningLabel {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("Input Level")
                ProgressView(value: model.inputLevel)
                Button(model.isMicTesting ? "Stop Mic Test" : "Start Mic Test") {
                    model.isMicTesting ? model.stopMicTest() : model.startMicTest()
                }
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
        .onChange(of: model.selectedInputDeviceID) { _, id in model.selectInputDevice(id: id) }
        .onChange(of: model.selectedOutputDeviceID) { _, id in model.selectOutputDevice(id: id) }
        .onChange(of: model.launchAtLogin) { _, _ in model.saveSettings() }
        .onChange(of: model.diagnosticsOptIn) { _, _ in model.saveSettings() }
    }
}
