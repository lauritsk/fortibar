import Foundation
import XCTest

final class VPNValidationTests: XCTestCase {
    func testAcceptsHostnameAndIPv4Address() throws {
        try VPNValidation.validate(
            host: "vpn.example.com",
            port: 443,
            username: "alice@example.com",
            password: Data("secret".utf8)
        )
        try VPNValidation.validate(
            host: "192.0.2.10",
            port: 10_443,
            username: "alice",
            password: Data("secret".utf8)
        )
    }

    func testRejectsHostThatCouldBecomeAnOptionOrPath() {
        for host in ["-v", "https://vpn.example.com", "vpn.example.com:443", "vpn/example"] {
            XCTAssertThrowsError(
                try VPNValidation.validate(
                    host: host,
                    port: 443,
                    username: "alice",
                    password: Data("secret".utf8)
                ),
                "Expected rejection for \(host)"
            )
        }
    }

    func testRejectsOutOfRangePort() {
        XCTAssertThrowsError(try validRequest(port: 0))
        XCTAssertThrowsError(try validRequest(port: 65_536))
    }

    func testRejectsLineBreaksInCredentials() {
        XCTAssertThrowsError(
            try VPNValidation.validate(
                host: "vpn.example.com",
                port: 443,
                username: "alice\nadmin",
                password: Data("secret".utf8)
            )
        )
        XCTAssertThrowsError(
            try VPNValidation.validate(
                host: "vpn.example.com",
                port: 443,
                username: "alice",
                password: Data("secret\nsecond-input".utf8)
            )
        )
    }

    func testValidatesSAMLSettings() throws {
        try VPNValidation.validateSAML(host: "vpn.example.com", port: 443, realm: "employees")
        XCTAssertThrowsError(
            try VPNValidation.validateSAML(
                host: "vpn.example.com",
                port: 443,
                realm: String(repeating: "a", count: 64)
            )
        )
    }

    func testExtractsAndValidatesSAMLLoginURL() {
        let value = "https://vpn.example.com:443/remote/saml/start?redirect=1&realm=employees"
        let log = "INFO:   Listening for SAML login on port 8020\nINFO:   Authenticate at '\(value)'\n"
        XCTAssertEqual(SAMLLogin.extractURLString(from: log), value)
        XCTAssertNotNil(SAMLLogin.validatedURL(
            from: value,
            expectedHost: "vpn.example.com",
            expectedPort: 443,
            expectedRealm: "employees"
        ))
        XCTAssertNil(SAMLLogin.validatedURL(
            from: "https://evil.example:443/remote/saml/start?redirect=1",
            expectedHost: "vpn.example.com",
            expectedPort: 443,
            expectedRealm: ""
        ))
    }

    func testEnforcesOpenFortiVPNFieldLimits() {
        XCTAssertThrowsError(
            try VPNValidation.validate(
                host: "vpn.example.com",
                port: 443,
                username: String(repeating: "a", count: 65),
                password: Data("secret".utf8)
            )
        )
        XCTAssertThrowsError(
            try VPNValidation.validate(
                host: "vpn.example.com",
                port: 443,
                username: "alice",
                password: Data(repeating: 97, count: 257)
            )
        )
    }

    private func validRequest(port: Int) throws {
        try VPNValidation.validate(
            host: "vpn.example.com",
            port: port,
            username: "alice",
            password: Data("secret".utf8)
        )
    }
}
