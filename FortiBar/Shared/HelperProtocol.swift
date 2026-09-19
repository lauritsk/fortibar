import Foundation

enum FortiBarIPC {
    static let machServiceName = "com.lauritsk.FortiBar.Helper"
    static let appBundleIdentifier = "com.lauritsk.FortiBar"
    static let helperSigningIdentifier = "FortiBarHelper"
    static let openFortiVPNSigningIdentifier = "com.lauritsk.FortiBar.openfortivpn"
    static let openFortiVPNExecutablePath = "/Library/PrivilegedHelperTools/com.lauritsk.FortiBar.openfortivpn"
    static let daemonPlistName = "com.lauritsk.FortiBar.Helper.plist"
}

enum VPNConnectionState: String {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed
}

enum VPNAuthenticationMethod: String, CaseIterable, Identifiable {
    case password
    case saml

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: "Password"
        case .saml: "SAML"
        }
    }
}

@objc protocol FortiBarHelperProtocol {
    func connect(
        host: String,
        port: Int,
        username: String,
        password: Data,
        authenticationMethod: String,
        realm: String,
        withReply reply: @escaping (String?) -> Void
    )

    func disconnect(withReply reply: @escaping (String?) -> Void)

    func status(withReply reply: @escaping (_ state: String, _ log: String, _ lastError: String, _ samlLoginURL: String) -> Void)
}
