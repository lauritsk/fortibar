import AppKit
import ServiceManagement
import SwiftUI

struct MenuContentView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var model: AppModel
    @State private var showsLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            Divider()

            connectionControl

            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            DisclosureGroup("Connection log", isExpanded: $showsLog) {
                VStack(alignment: .trailing, spacing: 6) {
                    ScrollView {
                        Text(model.log.isEmpty ? "No VPN activity yet." : model.log)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(logColor)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)

                    Button("Copy Log") { model.copyLog() }
                        .buttonStyle(.borderless)
                        .disabled(model.log.isEmpty)
                }
                .padding(.top, 6)
            }
            .font(.callout)

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Image("MenuBarIcon")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.stateTitle)
                    .font(.headline)
                Text(connectionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var connectionControl: some View {
        if model.helperStatus != .enabled {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Helper", systemImage: "gearshape.2")
                    Spacer()
                    Text(model.helperStatus.fortiBarDescription)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(model.helperStatus == .requiresApproval ? "Open Login Items" : "Set Up Helper") {
                    model.installOrApproveHelper()
                }
                .frame(maxWidth: .infinity)
                .controlSize(.large)
            }
        } else if model.canDisconnect {
            VStack(spacing: 8) {
                Button("Disconnect") { model.disconnect() }
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                if model.state == .connecting && !model.samlLoginURL.isEmpty {
                    Button("Open SAML Login") { model.openSAMLLogin() }
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            Button(model.authenticationMethod == .saml ? "Sign in and Connect" : "Connect") {
                model.connect()
            }
            .frame(maxWidth: .infinity)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canConnect)
        }
    }

    private var footer: some View {
        HStack {
            settingsControl

            Spacer()

            Button("Quit") { model.quit() }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
        }
        .foregroundStyle(.secondary)
    }

    private var settingsControl: some View {
        Button {
            openSettings()
            NSApplication.shared.activate()
        } label: {
            Label("Settings...", systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .keyboardShortcut(",", modifiers: .command)
    }

    private var connectionDescription: String {
        guard !model.host.isEmpty else { return "VPN not configured" }
        return "\(model.host):\(model.port) · \(model.authenticationMethod.title)"
    }

    private var statusColor: Color {
        switch model.state {
        case .connected: .green
        case .connecting, .disconnecting: .orange
        case .failed: .red
        case .disconnected: .secondary
        }
    }

    private var logColor: Color {
        model.log.isEmpty ? .secondary : .primary
    }

}
