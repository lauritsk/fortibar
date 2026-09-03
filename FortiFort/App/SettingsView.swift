import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("VPN") {
                Picker("Authentication", selection: $model.authenticationMethod) {
                    ForEach(VPNAuthenticationMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Host", text: $model.host, prompt: Text("vpn.example.com"))

                TextField("Port", value: $model.port, formatter: Self.portFormatter)

                if model.authenticationMethod == .password {
                    TextField("Username", text: $model.username)
                    HStack {
                        SecureField("Password", text: $model.password)
                        Button("Clear") { model.clearSavedPassword() }
                            .disabled(model.password.isEmpty)
                    }
                    Text("FortiFort saves the password to your login Keychain when you connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Realm", text: $model.realm, prompt: Text("Optional"))
                    Text("SAML authentication opens in your default browser. openfortivpn listens for the callback on 127.0.0.1:8020.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.canDisconnect)

            Section("Privileged helper") {
                LabeledContent("Status", value: model.helperStatus.fortiFortDescription)
                HStack {
                    if model.helperStatus == .enabled {
                        Button("Remove Helper") { model.removeHelper() }
                            .disabled(model.canDisconnect)
                    } else {
                        Button(model.helperStatus == .requiresApproval ? "Open Login Items" : "Install Helper") {
                            model.installOrApproveHelper()
                        }
                    }
                    Spacer()
                    if model.canDisconnect {
                        Text("Disconnect before changing the helper.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !model.errorMessage.isEmpty {
                Section {
                    Text(model.errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 440)
        .onChange(of: model.host) { model.saveSettings() }
        .onChange(of: model.port) { model.saveSettings() }
        .onChange(of: model.username) { model.saveSettings() }
        .onChange(of: model.authenticationMethod) { model.saveSettings() }
        .onChange(of: model.realm) { model.saveSettings() }
    }

    private static let portFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 65_535
        formatter.allowsFloats = false
        return formatter
    }()
}
