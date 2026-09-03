import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var host: String
    @Published var port: Int
    @Published var username: String
    @Published var password = ""
    @Published var authenticationMethod: VPNAuthenticationMethod
    @Published var realm: String
    @Published private(set) var state: VPNConnectionState = .disconnected
    @Published private(set) var log = ""
    @Published private(set) var errorMessage = ""
    @Published private(set) var samlLoginURL = ""
    @Published private(set) var helperStatus: SMAppService.Status

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let helper = HelperClient()
    private let installer = HelperInstaller()
    private var timer: Timer?
    private var openedSAMLURL = ""

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        host = defaults.string(forKey: "vpnHost") ?? ""
        let savedPort = defaults.integer(forKey: "vpnPort")
        port = savedPort == 0 ? 443 : savedPort
        username = defaults.string(forKey: "vpnUsername") ?? ""
        authenticationMethod = VPNAuthenticationMethod(
            rawValue: defaults.string(forKey: "authenticationMethod") ?? ""
        ) ?? .password
        realm = defaults.string(forKey: "samlRealm") ?? ""
        helperStatus = installer.status

        do {
            if let data = try keychain.loadPassword() {
                guard let savedPassword = String(data: data, encoding: .utf8) else {
                    throw VPNValidationError.invalidPassword
                }
                password = savedPassword
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    var canConnect: Bool {
        helperStatus == .enabled && state != .connecting && state != .connected && state != .disconnecting
    }

    var canDisconnect: Bool {
        state == .connecting || state == .connected
    }

    var stateTitle: String {
        switch state {
        case .disconnected: "Disconnected"
        case .connecting: samlLoginURL.isEmpty ? "Connecting" : "Waiting for SAML login"
        case .connected: "Connected"
        case .disconnecting: "Disconnecting"
        case .failed: "Connection failed"
        }
    }

    var symbolName: String {
        switch state {
        case .connected: "lock.shield.fill"
        case .connecting, .disconnecting: "shield.lefthalf.filled"
        case .failed: "exclamationmark.shield.fill"
        case .disconnected: "shield"
        }
    }

    var statusColorName: String {
        switch state {
        case .connected: "green"
        case .connecting, .disconnecting: "orange"
        case .failed: "red"
        case .disconnected: "secondary"
        }
    }

    func saveSettings() {
        defaults.set(host.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "vpnHost")
        defaults.set(port, forKey: "vpnPort")
        defaults.set(username, forKey: "vpnUsername")
        defaults.set(authenticationMethod.rawValue, forKey: "authenticationMethod")
        defaults.set(realm, forKey: "samlRealm")
    }

    func connect() {
        errorMessage = ""
        samlLoginURL = ""
        openedSAMLURL = ""
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwordData = Data(password.utf8)

        do {
            switch authenticationMethod {
            case .password:
                try VPNValidation.validate(host: normalizedHost, port: port, username: username, password: passwordData)
            case .saml:
                try VPNValidation.validateSAML(host: normalizedHost, port: port, realm: realm)
            }
            guard helperStatus == .enabled else {
                throw AppModelError.helperNotReady
            }
            host = normalizedHost
            saveSettings()
            if authenticationMethod == .password {
                try keychain.savePassword(passwordData)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        state = .connecting
        let transmittedPassword = authenticationMethod == .password ? passwordData : Data()
        helper.connect(
            host: normalizedHost,
            port: port,
            username: authenticationMethod == .password ? username : "",
            password: transmittedPassword,
            authenticationMethod: authenticationMethod,
            realm: authenticationMethod == .saml ? realm : ""
        ) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.state = .failed
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.refreshStatus()
                }
            }
        }
    }

    func disconnect() {
        state = .disconnecting
        errorMessage = ""
        samlLoginURL = ""
        helper.disconnect { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.state = .failed
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.refreshStatus()
                }
            }
        }
    }

    func installOrApproveHelper() {
        errorMessage = ""
        do {
            switch installer.status {
            case .enabled:
                break
            case .requiresApproval:
                installer.openApprovalSettings()
            case .notRegistered, .notFound:
                try installer.register()
                if installer.status == .requiresApproval {
                    installer.openApprovalSettings()
                }
            @unknown default:
                throw AppModelError.unknownHelperStatus
            }
            refresh()
        } catch {
            helperStatus = installer.status
            errorMessage = error.localizedDescription
            if helperStatus == .requiresApproval {
                installer.openApprovalSettings()
            }
        }
    }

    func removeHelper() {
        guard state != .connecting && state != .connected && state != .disconnecting else {
            errorMessage = "Disconnect the VPN before removing the helper."
            return
        }
        do {
            try installer.unregister()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openSAMLLogin() {
        guard let url = SAMLLogin.validatedURL(
            from: samlLoginURL,
            expectedHost: host,
            expectedPort: port,
            expectedRealm: realm
        ) else {
            errorMessage = "openfortivpn returned an unexpected SAML login URL."
            return
        }
        openedSAMLURL = samlLoginURL
        NSWorkspace.shared.open(url)
    }

    func clearSavedPassword() {
        do {
            try keychain.deletePassword()
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log, forType: .string)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refresh() {
        helperStatus = installer.status
        if helperStatus == .enabled {
            refreshStatus()
        } else if state == .connecting || state == .connected || state == .disconnecting {
            state = .disconnected
        }
    }

    private func refreshStatus() {
        helper.status { [weak self] state, log, helperError, samlLoginURL in
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = state
                self.log = log
                self.samlLoginURL = samlLoginURL
                if !helperError.isEmpty {
                    self.errorMessage = helperError
                }
                if state == .connecting,
                   self.authenticationMethod == .saml,
                   !samlLoginURL.isEmpty,
                   self.openedSAMLURL != samlLoginURL {
                    self.openSAMLLogin()
                }
            }
        } failure: { [weak self] error in
            DispatchQueue.main.async {
                guard self?.helperStatus == .enabled else { return }
                self?.errorMessage = "Helper connection failed: \(error.localizedDescription)"
            }
        }
    }
}

enum AppModelError: LocalizedError {
    case helperNotReady
    case unknownHelperStatus

    var errorDescription: String? {
        switch self {
        case .helperNotReady: "Install and approve the privileged helper first."
        case .unknownHelperStatus: "macOS returned an unknown helper status."
        }
    }
}
