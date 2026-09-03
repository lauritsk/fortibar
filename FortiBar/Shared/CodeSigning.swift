import Foundation
import Security

enum CodeSigningRequirement {
    static func forPeer(identifier: String) throws -> String {
        guard identifier.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil else {
            throw CodeSigningError.invalidIdentifier
        }

        var currentCode: SecCode?
        guard SecCodeCopySelf([], &currentCode) == errSecSuccess, let currentCode else {
            throw CodeSigningError.cannotReadSignature
        }

        guard SecCodeCheckValidity(currentCode, [], nil) == errSecSuccess else {
            throw CodeSigningError.cannotReadSignature
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(currentCode, [], &staticCode) == errSecSuccess, let staticCode else {
            throw CodeSigningError.cannotReadSignature
        }

        var signingInformation: CFDictionary?
        let status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard status == errSecSuccess,
              let information = signingInformation as? [String: Any],
              let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String,
              teamIdentifier.range(of: #"^[A-Z0-9]+$"#, options: .regularExpression) != nil else {
            throw CodeSigningError.missingTeamIdentifier
        }

        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

enum CodeSigningError: LocalizedError {
    case cannotReadSignature
    case missingTeamIdentifier
    case invalidIdentifier

    var errorDescription: String? {
        switch self {
        case .cannotReadSignature:
            "FortiBar could not inspect its code signature."
        case .missingTeamIdentifier:
            "FortiBar and its helper must be signed with an Apple development or Developer ID certificate."
        case .invalidIdentifier:
            "The helper has an invalid signing identifier."
        }
    }
}
