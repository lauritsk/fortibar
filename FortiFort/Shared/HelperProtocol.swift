import Foundation

enum FortiFortIPC {
    static let machServiceName = "com.lauritsk.FortiFort.Helper"
    static let appBundleIdentifier = "com.lauritsk.FortiFort"
    static let helperBundleIdentifier = "com.lauritsk.FortiFort.Helper"
    static let daemonPlistName = "com.lauritsk.FortiFort.Helper.plist"
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

@objc protocol FortiFortHelperProtocol {
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
