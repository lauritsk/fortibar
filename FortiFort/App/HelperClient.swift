import Foundation

final class HelperClient {
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    deinit {
        lock.lock()
        connection?.invalidate()
        connection = nil
        lock.unlock()
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        password: Data,
        authenticationMethod: VPNAuthenticationMethod,
        realm: String,
        completion: @escaping (Error?) -> Void
    ) {
        do {
            let proxy = try remoteProxy(errorHandler: { completion($0) })
            proxy.connect(
                host: host,
                port: port,
                username: username,
                password: password,
                authenticationMethod: authenticationMethod.rawValue,
                realm: realm
            ) { message in
                completion(message.map(HelperClientError.remote))
            }
        } catch {
            completion(error)
        }
    }

    func disconnect(completion: @escaping (Error?) -> Void) {
        do {
            let proxy = try remoteProxy(errorHandler: { completion($0) })
            proxy.disconnect { message in
                completion(message.map(HelperClientError.remote))
            }
        } catch {
            completion(error)
        }
    }

    func status(completion: @escaping (VPNConnectionState, String, String, String) -> Void, failure: @escaping (Error) -> Void) {
        do {
            let proxy = try remoteProxy(errorHandler: failure)
            proxy.status { state, log, lastError, samlLoginURL in
                completion(VPNConnectionState(rawValue: state) ?? .failed, log, lastError, samlLoginURL)
            }
        } catch {
            failure(error)
        }
    }

    private func remoteProxy(errorHandler: @escaping (Error) -> Void) throws -> FortiFortHelperProtocol {
        lock.lock()
        defer { lock.unlock() }

        if connection == nil {
            let newConnection = NSXPCConnection(
                machServiceName: FortiFortIPC.machServiceName,
                options: .privileged
            )
            newConnection.remoteObjectInterface = NSXPCInterface(with: FortiFortHelperProtocol.self)
            let requirement = try CodeSigningRequirement.forPeer(identifier: FortiFortIPC.helperBundleIdentifier)
            newConnection.setCodeSigningRequirement(requirement)
            newConnection.invalidationHandler = { [weak self, weak newConnection] in
                self?.discard(newConnection)
            }
            newConnection.interruptionHandler = { [weak self, weak newConnection] in
                self?.discard(newConnection)
            }
            newConnection.activate()
            connection = newConnection
        }

        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
            errorHandler(error)
        }) as? FortiFortHelperProtocol else {
            throw HelperClientError.noProxy
        }
        return proxy
    }

    private func discard(_ discardedConnection: NSXPCConnection?) {
        lock.lock()
        if connection === discardedConnection {
            connection = nil
        }
        lock.unlock()
    }
}

enum HelperClientError: LocalizedError {
    case noProxy
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .noProxy: "Could not create a connection to the privileged helper."
        case .remote(let message): message
        }
    }
}
