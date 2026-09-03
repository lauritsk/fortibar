import Foundation

enum VPNValidation {
    static let maximumHostBytes = 253
    static let maximumUsernameBytes = 64
    static let maximumPasswordBytes = 256
    static let maximumRealmBytes = 63

    static func validate(host: String, port: Int, username: String, password: Data) throws {
        try validateEndpoint(host: host, port: port)
        guard !username.isEmpty else { throw VPNValidationError.emptyUsername }
        guard username.utf8.count <= maximumUsernameBytes else { throw VPNValidationError.usernameTooLong }
        guard !containsForbiddenControlCharacter(username) else {
            throw VPNValidationError.invalidUsername
        }
        guard !password.isEmpty else { throw VPNValidationError.emptyPassword }
        guard password.count <= maximumPasswordBytes else { throw VPNValidationError.passwordTooLong }
        guard !password.contains(0), !password.contains(10), !password.contains(13) else {
            throw VPNValidationError.invalidPassword
        }
        guard String(data: password, encoding: .utf8) != nil else { throw VPNValidationError.invalidPassword }
    }

    static func validateSAML(host: String, port: Int, realm: String) throws {
        try validateEndpoint(host: host, port: port)
        guard realm.utf8.count <= maximumRealmBytes else { throw VPNValidationError.realmTooLong }
        guard !containsForbiddenControlCharacter(realm) else { throw VPNValidationError.invalidRealm }
    }

    private static func validateEndpoint(host: String, port: Int) throws {
        guard !host.isEmpty else { throw VPNValidationError.emptyHost }
        guard host.utf8.count <= maximumHostBytes else { throw VPNValidationError.hostTooLong }
        guard host.unicodeScalars.allSatisfy({ scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-")
        }), !host.hasPrefix("-"), !host.hasSuffix("-"), !host.contains("..") else {
            throw VPNValidationError.invalidHost
        }
        guard (1...65_535).contains(port) else { throw VPNValidationError.invalidPort }
    }

    private static func containsForbiddenControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value == 0 || $0.value == 10 || $0.value == 13 }
    }
}

enum VPNValidationError: LocalizedError, Equatable {
    case emptyHost
    case invalidHost
    case hostTooLong
    case invalidPort
    case emptyUsername
    case invalidUsername
    case usernameTooLong
    case emptyPassword
    case invalidPassword
    case passwordTooLong
    case invalidRealm
    case realmTooLong

    var errorDescription: String? {
        switch self {
        case .emptyHost: "Enter the VPN hostname."
        case .invalidHost: "Use a hostname or IPv4 address without a scheme, path, or port."
        case .hostTooLong: "The hostname is too long."
        case .invalidPort: "The port must be between 1 and 65535."
        case .emptyUsername: "Enter the VPN username."
        case .invalidUsername: "The username cannot contain line breaks or null bytes."
        case .usernameTooLong: "The username is too long for openfortivpn."
        case .emptyPassword: "Enter the VPN password."
        case .invalidPassword: "The password must be UTF-8 and cannot contain line breaks or null bytes."
        case .passwordTooLong: "The password is too long for openfortivpn."
        case .invalidRealm: "The SAML realm cannot contain line breaks or null bytes."
        case .realmTooLong: "The SAML realm is too long for openfortivpn."
        }
    }
}
