import SwiftUI

struct AppShellView: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        Group {
            if model.authenticationState == .signedOut {
                SignedOutView(model: model)
            } else {
                SignedInShellView(model: model)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SignedOutView: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Toki")
                .font(.system(size: 28, weight: .semibold))
            Text("Private team push-to-talk, scoped to one active room.")
                .foregroundStyle(.secondary)
            TextField("Invited email", text: $model.signInEmail)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
            Picker("Permission preset", selection: $model.permissionPreset) {
                ForEach(AppShellModel.PermissionPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            Button("Sign In") {
                Task { await model.signIn() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.signInEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let signInError = model.signInError {
                Text(signInError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(40)
    }
}

private struct SignedInShellView: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ConversationSidebar(model: model)
                Divider()
                ActiveRoomPanel(model: model)
            }
            Divider()
            StatusStrip(model: model)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Reconnect") {
                    model.simulateReconnect()
                }
                Button("P2P Down") {
                    model.simulateP2PUnavailable()
                }
                Button("Restore") {
                    model.restoreConnectedState()
                }
                Button("Remote Floor") {
                    model.simulateRemoteSpeaker()
                }
                Button("Sign Out") {
                    model.signOut()
                }
            }
        }
    }
}

private struct ConversationSidebar: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rooms")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            List(model.rooms, selection: Binding(
                get: { model.activeConversationID },
                set: { newValue in
                    guard let newValue else { return }
                    model.selectRoom(newValue)
                }
            )) { room in
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.title)
                    Text(room.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 260, maxHeight: .infinity)
    }
}

private struct ActiveRoomPanel: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.selectedRoom?.title ?? "No Room Selected")
                        .font(.title2.weight(.semibold))
                    Text(model.detailStatus)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Permissions", selection: $model.permissionPreset) {
                    ForEach(AppShellModel.PermissionPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .frame(width: 220)
            }

            if model.permissionPreset == .microphoneDenied {
                PermissionBanner(
                    title: "Microphone access is required",
                    message: "Toki fails closed when microphone permission is denied. PTT remains disabled until access is restored.",
                    actionTitle: "Request Access",
                    action: {
                        Task { await model.requestMicrophonePermission() }
                    }
                )
            }

            if model.permissionPreset == .inputMonitoringDenied {
                PermissionBanner(
                    title: "Global shortcut access is unavailable",
                    message: "Keyboard PTT is blocked, but the in-window hold-to-talk button remains available.",
                    actionTitle: "Refresh Access",
                    action: model.refreshInputMonitoringPermission
                )
            }

            HStack(spacing: 12) {
                SummaryMetric(title: "Participants", value: "\(model.selectedRoom?.participants ?? 0)")
                SummaryMetric(title: "Output", value: model.isOutputMuted ? "Muted" : "Live")
                SummaryMetric(title: "Speaker", value: model.activeSpeakerLabel ?? "None")
                SummaryMetric(title: "Shortcut", value: model.canUseKeyboardPTT ? "Ready" : "Blocked")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Input")
                    ProgressView(value: model.inputLevel)
                    Text(model.isMicTesting ? "Testing" : "Idle")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Output")
                    ProgressView(value: model.activeOutputLevel)
                    Text(model.activeSpeakerLabel ?? "No speaker")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                HoldToTalkButton(
                    title: "Hold To Talk",
                    isEnabled: model.canUseManualPTT,
                    onPress: model.startManualPushToTalk,
                    onRelease: model.stopPushToTalk
                )
                Button(model.isOutputMuted ? "Unmute Output" : "Mute Output") {
                    model.isOutputMuted.toggle()
                }
                .buttonStyle(.bordered)
                Button("Replay \(model.replayAvailableDurationLabel)") {
                    model.playRecentReplay()
                }
                .buttonStyle(.bordered)
                .disabled(!model.canPlayReplay)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct StatusStrip: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.menuBarStatus.symbolName)
            Text(model.activityLabel)
                .fontWeight(.medium)
            Text(model.detailStatus)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let activeSpeakerLabel = model.activeSpeakerLabel {
                Text("Speaker: \(activeSpeakerLabel)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(model.pushToTalkShortcutLabel)
                .foregroundStyle(.secondary)
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct PermissionBanner: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HoldToTalkButton: View {
    let title: String
    let isEnabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var isHolding = false

    var body: some View {
        Button(title) {}
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHolding else { return }
                        isHolding = true
                        onPress()
                    }
                    .onEnded { _ in
                        isHolding = false
                        onRelease()
                    }
            )
    }
}
