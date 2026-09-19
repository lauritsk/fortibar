import Darwin
import Foundation
import Security

enum PrivilegedExecutableValidator {
    private static let hardenedRuntimeSignatureFlag: UInt32 = 0x10000

    static func validate(
        executableURL: URL,
        signingRequirement: String,
        requiredOwner: uid_t = 0
    ) throws {
        guard executableURL.isFileURL else {
            throw PrivilegedExecutableValidationError.invalidPath
        }

        let standardizedURL = executableURL.standardizedFileURL
        guard standardizedURL.path == executableURL.path,
              standardizedURL.path.hasPrefix("/") else {
            throw PrivilegedExecutableValidationError.invalidPath
        }

        try validateSecureFilesystemPath(standardizedURL, requiredOwner: requiredOwner)
        try validateCodeSignature(of: standardizedURL, requirementText: signingRequirement)
        try validateSecureFilesystemPath(standardizedURL, requiredOwner: requiredOwner)
    }

    static func validateFileMetadata(
        mode: mode_t,
        owner: uid_t,
        requiredOwner: uid_t,
        isExecutable: Bool
    ) throws {
        guard owner == requiredOwner else {
            throw PrivilegedExecutableValidationError.insecureOwner
        }
        guard mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw PrivilegedExecutableValidationError.notRegularFile
        }
        guard mode & mode_t(S_IWGRP | S_IWOTH) == 0 else {
            throw PrivilegedExecutableValidationError.insecurePermissions
        }
        guard isExecutable else {
            throw PrivilegedExecutableValidationError.notExecutable
        }
    }

    static func validateDirectoryMetadata(
        mode: mode_t,
        owner: uid_t,
        requiredOwner: uid_t
    ) throws {
        guard owner == requiredOwner else {
            throw PrivilegedExecutableValidationError.insecureOwner
        }
        guard mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw PrivilegedExecutableValidationError.insecureDirectory
        }
        guard mode & mode_t(S_IWGRP | S_IWOTH) == 0 else {
            throw PrivilegedExecutableValidationError.insecurePermissions
        }
    }

    static func validateSecureFilesystemPath(
        _ executableURL: URL,
        requiredOwner: uid_t = 0
    ) throws {
        var currentURL = executableURL
        var isExecutable = true

        while true {
            var metadata = stat()
            guard lstat(currentURL.path, &metadata) == 0 else {
                throw PrivilegedExecutableValidationError.cannotInspectPath(errno)
            }

            try validateNoAccessControlList(atPath: currentURL.path)

            if isExecutable {
                try validateFileMetadata(
                    mode: metadata.st_mode,
                    owner: metadata.st_uid,
                    requiredOwner: requiredOwner,
                    isExecutable: metadata.st_mode & mode_t(S_IXUSR | S_IXGRP | S_IXOTH) != 0
                )
                isExecutable = false
            } else {
                try validateDirectoryMetadata(
                    mode: metadata.st_mode,
                    owner: metadata.st_uid,
                    requiredOwner: requiredOwner
                )
            }

            if currentURL.path == "/" { break }
            currentURL.deleteLastPathComponent()
        }
    }

    private static func validateNoAccessControlList(atPath path: String) throws {
        errno = 0
        guard let accessControlList = acl_get_link_np(path, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT { return }
            throw PrivilegedExecutableValidationError.cannotInspectPath(errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(accessControlList)) }

        var entry: acl_entry_t?
        switch acl_get_entry(accessControlList, ACL_FIRST_ENTRY.rawValue, &entry) {
        case 0:
            return
        case 1:
            throw PrivilegedExecutableValidationError.insecureAccessControlList
        default:
            throw PrivilegedExecutableValidationError.cannotInspectPath(errno)
        }
    }

    private static func validateCodeSignature(of executableURL: URL, requirementText: String) throws {
        var staticCode: SecStaticCode?
        let createCodeStatus = SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode)
        guard createCodeStatus == errSecSuccess, let staticCode else {
            throw PrivilegedExecutableValidationError.invalidCodeSignature(createCodeStatus)
        }

        var requirement: SecRequirement?
        let createRequirementStatus = SecRequirementCreateWithString(
            requirementText as CFString,
            [],
            &requirement
        )
        guard createRequirementStatus == errSecSuccess, let requirement else {
            throw PrivilegedExecutableValidationError.invalidSigningRequirement(createRequirementStatus)
        }

        let validationFlags = SecCSFlags(
            rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures
        )
        let validationStatus = SecStaticCodeCheckValidity(staticCode, validationFlags, requirement)
        guard validationStatus == errSecSuccess else {
            throw PrivilegedExecutableValidationError.invalidCodeSignature(validationStatus)
        }

        var signingInformation: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard informationStatus == errSecSuccess,
              let information = signingInformation as? [String: Any],
              let flags = information[kSecCodeInfoFlags as String] as? NSNumber,
              flags.uint32Value & hardenedRuntimeSignatureFlag != 0 else {
            throw PrivilegedExecutableValidationError.hardenedRuntimeRequired
        }

        let entitlements = information[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        let unsafeEntitlements = [
            "com.apple.security.cs.allow-dyld-environment-variables",
            "com.apple.security.cs.allow-unsigned-executable-memory",
            "com.apple.security.cs.disable-executable-page-protection",
            "com.apple.security.cs.disable-library-validation",
            "com.apple.security.get-task-allow"
        ]
        guard unsafeEntitlements.allSatisfy({ entitlements[$0] as? Bool != true }) else {
            throw PrivilegedExecutableValidationError.unsafeCodeSigningEntitlements
        }
    }
}

enum PrivilegedExecutableValidationError: LocalizedError, Equatable {
    case invalidPath
    case cannotInspectPath(Int32)
    case insecureOwner
    case insecurePermissions
    case insecureAccessControlList
    case notRegularFile
    case insecureDirectory
    case notExecutable
    case invalidSigningRequirement(OSStatus)
    case invalidCodeSignature(OSStatus)
    case hardenedRuntimeRequired
    case unsafeCodeSigningEntitlements

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            "The privileged executable path is invalid."
        case .cannotInspectPath(let errorNumber):
            "The privileged executable path could not be inspected: \(String(cString: strerror(errorNumber)))."
        case .insecureOwner:
            "The privileged executable and its parent directories must be owned by root."
        case .insecurePermissions:
            "The privileged executable and its parent directories cannot be writable by group or other users."
        case .insecureAccessControlList:
            "The privileged executable and its parent directories cannot have extended access controls."
        case .notRegularFile:
            "The privileged executable must be a regular file, not a symbolic link."
        case .insecureDirectory:
            "A component of the privileged executable path is not a directory."
        case .notExecutable:
            "The privileged executable does not have an executable permission bit."
        case .invalidSigningRequirement(let status):
            "FortiBar could not create the executable signing requirement (status \(status))."
        case .invalidCodeSignature(let status):
            "The privileged executable has an invalid or untrusted code signature (status \(status))."
        case .hardenedRuntimeRequired:
            "The privileged executable was not signed with the hardened runtime."
        case .unsafeCodeSigningEntitlements:
            "The privileged executable has code-signing entitlements that are unsafe for root execution."
        }
    }
}
