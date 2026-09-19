import Darwin
import Foundation
import XCTest

final class PrivilegedExecutableValidatorTests: XCTestCase {
    func testAcceptsSecureSystemExecutablePath() throws {
        try PrivilegedExecutableValidator.validateSecureFilesystemPath(
            URL(fileURLWithPath: "/usr/bin/true")
        )
    }

    func testAcceptsRootOwnedReadOnlyExecutableMetadata() throws {
        try PrivilegedExecutableValidator.validateFileMetadata(
            mode: mode_t(S_IFREG | 0o755),
            owner: 0,
            requiredOwner: 0,
            isExecutable: true
        )
    }

    func testRejectsExecutableOwnedByAUser() {
        XCTAssertThrowsError(
            try PrivilegedExecutableValidator.validateFileMetadata(
                mode: mode_t(S_IFREG | 0o755),
                owner: 501,
                requiredOwner: 0,
                isExecutable: true
            )
        ) { error in
            XCTAssertEqual(error as? PrivilegedExecutableValidationError, .insecureOwner)
        }
    }

    func testRejectsWritableExecutable() {
        for mode in [mode_t(S_IFREG | 0o775), mode_t(S_IFREG | 0o757)] {
            XCTAssertThrowsError(
                try PrivilegedExecutableValidator.validateFileMetadata(
                    mode: mode,
                    owner: 0,
                    requiredOwner: 0,
                    isExecutable: true
                )
            ) { error in
                XCTAssertEqual(error as? PrivilegedExecutableValidationError, .insecurePermissions)
            }
        }
    }

    func testRejectsSymlinkAndNonExecutableFile() {
        XCTAssertThrowsError(
            try PrivilegedExecutableValidator.validateFileMetadata(
                mode: mode_t(S_IFLNK | 0o755),
                owner: 0,
                requiredOwner: 0,
                isExecutable: true
            )
        ) { error in
            XCTAssertEqual(error as? PrivilegedExecutableValidationError, .notRegularFile)
        }

        XCTAssertThrowsError(
            try PrivilegedExecutableValidator.validateFileMetadata(
                mode: mode_t(S_IFREG | 0o644),
                owner: 0,
                requiredOwner: 0,
                isExecutable: false
            )
        ) { error in
            XCTAssertEqual(error as? PrivilegedExecutableValidationError, .notExecutable)
        }
    }

    func testRejectsWritableOrUserOwnedParentDirectory() {
        XCTAssertThrowsError(
            try PrivilegedExecutableValidator.validateDirectoryMetadata(
                mode: mode_t(S_IFDIR | 0o775),
                owner: 0,
                requiredOwner: 0
            )
        ) { error in
            XCTAssertEqual(error as? PrivilegedExecutableValidationError, .insecurePermissions)
        }

        XCTAssertThrowsError(
            try PrivilegedExecutableValidator.validateDirectoryMetadata(
                mode: mode_t(S_IFDIR | 0o755),
                owner: 501,
                requiredOwner: 0
            )
        ) { error in
            XCTAssertEqual(error as? PrivilegedExecutableValidationError, .insecureOwner)
        }
    }
}
