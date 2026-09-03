import Foundation

enum SAMLLogin {
    static let callbackPort = 8020
    private static let logMarker = "Authenticate at '"

    static func extractURLString(from log: String) -> String? {
        guard let markerRange = log.range(of: logMarker, options: .backwards) else { return nil }
        let remainder = log[markerRange.upperBound...]
        guard let closingQuote = remainder.firstIndex(of: "'") else { return nil }
        let value = String(remainder[..<closingQuote])
        return value.isEmpty ? nil : value
    }

    static func validatedURL(
        from value: String,
        expectedHost: String,
        expectedPort: Int,
        expectedRealm: String
    ) -> URL? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == expectedHost.lowercased(),
              components.port == expectedPort,
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.path == "/remote/saml/start",
              let queryItems = components.queryItems,
              queryItems.contains(where: { $0.name == "redirect" && $0.value == "1" }),
              queryItems.allSatisfy({ $0.name == "redirect" || $0.name == "realm" }),
              queryItems.filter({ $0.name == "redirect" }).count == 1 else {
            return nil
        }
        let realmItems = queryItems.filter { $0.name == "realm" }
        if expectedRealm.isEmpty {
            guard realmItems.isEmpty else { return nil }
        } else {
            guard realmItems.count == 1, realmItems[0].value == expectedRealm else { return nil }
        }
        return components.url
    }
}
