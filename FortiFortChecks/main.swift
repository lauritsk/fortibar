import Foundation

@main
struct ValidationChecks {
    static func main() throws {
        try expectValid(host: "vpn.example.com", port: 443, username: "alice@example.com", password: "secret")
        try expectValid(host: "192.0.2.10", port: 10_443, username: "alice", password: "secret")

        for host in ["-v", "https://vpn.example.com", "vpn.example.com:443", "vpn/example"] {
            expectInvalid(host: host, port: 443, username: "alice", password: "secret")
        }
        expectInvalid(host: "vpn.example.com", port: 0, username: "alice", password: "secret")
        expectInvalid(host: "vpn.example.com", port: 65_536, username: "alice", password: "secret")
        expectInvalid(host: "vpn.example.com", port: 443, username: "alice\nadmin", password: "secret")
        expectInvalid(host: "vpn.example.com", port: 443, username: "alice", password: "secret\nsecond-input")
        expectInvalid(host: "vpn.example.com", port: 443, username: String(repeating: "a", count: 65), password: "secret")
        expectInvalid(host: "vpn.example.com", port: 443, username: "alice", password: String(repeating: "a", count: 257))

        try VPNValidation.validateSAML(host: "vpn.example.com", port: 443, realm: "employees")
        do {
            try VPNValidation.validateSAML(
                host: "vpn.example.com",
                port: 443,
                realm: String(repeating: "a", count: 64)
            )
            fputs("Expected an overlong SAML realm to fail\n", stderr)
            exit(EXIT_FAILURE)
        } catch {
            // Expected.
        }

        let loginURL = "https://vpn.example.com:443/remote/saml/start?redirect=1&realm=employees"
        let log = "INFO:   Authenticate at '\(loginURL)'\n"
        guard SAMLLogin.extractURLString(from: log) == loginURL,
              SAMLLogin.validatedURL(
                from: loginURL,
                expectedHost: "vpn.example.com",
                expectedPort: 443,
                expectedRealm: "employees"
              ) != nil,
              SAMLLogin.validatedURL(
                from: "https://evil.example:443/remote/saml/start?redirect=1",
                expectedHost: "vpn.example.com",
                expectedPort: 443,
                expectedRealm: ""
              ) == nil else {
            fputs("SAML URL checks failed\n", stderr)
            exit(EXIT_FAILURE)
        }

        print("Validation checks passed")
    }

    private static func expectValid(host: String, port: Int, username: String, password: String) throws {
        try VPNValidation.validate(
            host: host,
            port: port,
            username: username,
            password: Data(password.utf8)
        )
    }

    private static func expectInvalid(host: String, port: Int, username: String, password: String) {
        do {
            try expectValid(host: host, port: port, username: username, password: password)
            fputs("Expected validation failure for \(host):\(port)\n", stderr)
            exit(EXIT_FAILURE)
        } catch {
            return
        }
    }
}
