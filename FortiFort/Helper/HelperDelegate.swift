import Foundation

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    let runner: VPNRunner

    init(runner: VPNRunner) {
        self.runner = runner
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard newConnection.effectiveUserIdentifier != 0 else {
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: FortiFortHelperProtocol.self)
        newConnection.exportedObject = HelperService(runner: runner)
        newConnection.activate()
        return true
    }
}

final class HelperService: NSObject, FortiFortHelperProtocol {
    private let runner: VPNRunner

    init(runner: VPNRunner) {
        self.runner = runner
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        password: Data,
        authenticationMethod: String,
        realm: String,
        withReply reply: @escaping (String?) -> Void
    ) {
        reply(runner.connect(
            host: host,
            port: port,
            username: username,
            password: password,
            authenticationMethod: authenticationMethod,
            realm: realm
        ))
    }

    func disconnect(withReply reply: @escaping (String?) -> Void) {
        reply(runner.disconnect())
    }

    func status(withReply reply: @escaping (String, String, String, String) -> Void) {
        let snapshot = runner.snapshot()
        reply(snapshot.0.rawValue, snapshot.1, snapshot.2, snapshot.3)
    }
}
