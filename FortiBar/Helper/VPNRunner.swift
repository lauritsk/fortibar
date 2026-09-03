import Foundation

final class VPNRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var outputHandle: FileHandle?
    private var connectionState: VPNConnectionState = .disconnected
    private var logText = ""
    private var lastError = ""
    private var samlLoginURL = ""
    private var requestedStop = false

    func connect(
        host: String,
        port: Int,
        username: String,
        password: Data,
        authenticationMethod: String,
        realm: String
    ) -> String? {
        guard let method = VPNAuthenticationMethod(rawValue: authenticationMethod) else {
            return "The requested authentication method is invalid."
        }
        do {
            switch method {
            case .password:
                try VPNValidation.validate(host: host, port: port, username: username, password: password)
            case .saml:
                try VPNValidation.validateSAML(host: host, port: port, realm: realm)
            }
        } catch {
            return error.localizedDescription
        }

        lock.lock()
        guard process == nil else {
            lock.unlock()
            return "A VPN connection is already running."
        }
        connectionState = .connecting
        lastError = ""
        logText = ""
        samlLoginURL = ""
        requestedStop = false
        lock.unlock()

        let executable: URL
        do {
            executable = try OpenFortiVPNLocator.executableURL()
        } catch {
            fail(error.localizedDescription)
            return error.localizedDescription
        }

        let newProcess = Process()
        let output = Pipe()
        let input: Pipe?
        var arguments = ["--config=/dev/null"]
        switch method {
        case .password:
            input = Pipe()
            arguments.append("--username=\(username)")
            newProcess.standardInput = input
        case .saml:
            input = nil
            arguments.append("--saml-login=\(SAMLLogin.callbackPort)")
            if !realm.isEmpty {
                arguments.append("--realm=\(realm)")
            }
            newProcess.standardInput = FileHandle.nullDevice
        }
        arguments.append("\(host):\(port)")
        newProcess.executableURL = executable
        newProcess.arguments = arguments
        newProcess.standardOutput = output
        newProcess.standardError = output
        newProcess.environment = [
            "HOME": "/var/root",
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        newProcess.terminationHandler = { [weak self] finishedProcess in
            self?.processFinished(finishedProcess)
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                self?.appendOutput(data)
            }
        }

        lock.lock()
        process = newProcess
        outputHandle = output.fileHandleForReading
        appendLocked("Starting \(executable.path)\n")
        lock.unlock()

        do {
            try newProcess.run()
            if let input {
                var secretInput = password
                secretInput.append(10)
                try input.fileHandleForWriting.write(contentsOf: secretInput)
                secretInput.resetBytes(in: secretInput.startIndex..<secretInput.endIndex)
                try input.fileHandleForWriting.close()
            }
            return nil
        } catch {
            try? input?.fileHandleForWriting.close()
            output.fileHandleForReading.readabilityHandler = nil
            lock.lock()
            process = nil
            outputHandle = nil
            connectionState = .failed
            lastError = "Could not start openfortivpn: \(error.localizedDescription)"
            appendLocked(lastError + "\n")
            lock.unlock()
            return lastError
        }
    }

    func disconnect() -> String? {
        lock.lock()
        guard let runningProcess = process else {
            connectionState = .disconnected
            lock.unlock()
            return nil
        }
        guard connectionState != .disconnecting else {
            lock.unlock()
            return nil
        }
        requestedStop = true
        connectionState = .disconnecting
        appendLocked("Disconnect requested.\n")
        lock.unlock()

        runningProcess.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if runningProcess.isRunning {
                runningProcess.terminate()
            }
        }
        return nil
    }

    func snapshot() -> (VPNConnectionState, String, String, String) {
        lock.lock()
        defer { lock.unlock() }
        return (connectionState, logText, lastError, samlLoginURL)
    }

    private func appendOutput(_ data: Data) {
        let chunk = String(decoding: data, as: UTF8.self)
        lock.lock()
        appendLocked(chunk)
        if let extractedURL = SAMLLogin.extractURLString(from: logText) {
            samlLoginURL = extractedURL
        }
        if logText.contains("Tunnel is up and running.") && connectionState == .connecting {
            connectionState = .connected
        }
        lock.unlock()
    }

    private func processFinished(_ finishedProcess: Process) {
        lock.lock()
        guard process === finishedProcess else {
            lock.unlock()
            return
        }
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        process = nil
        let stoppedByRequest = requestedStop
        requestedStop = false
        samlLoginURL = ""

        if stoppedByRequest || finishedProcess.terminationStatus == 0 {
            connectionState = .disconnected
            lastError = ""
            appendLocked("VPN stopped.\n")
        } else {
            connectionState = .failed
            lastError = "openfortivpn exited with status \(finishedProcess.terminationStatus). See the log for details."
            appendLocked(lastError + "\n")
        }
        lock.unlock()
    }

    private func fail(_ message: String) {
        lock.lock()
        connectionState = .failed
        lastError = message
        appendLocked(message + "\n")
        lock.unlock()
    }

    private func appendLocked(_ text: String) {
        logText.append(contentsOf: text.filter { character in
            character == "\n" || character == "\t" || !character.isASCII || character.asciiValue.map { $0 >= 32 } == true
        })
        let maximumCharacters = 32_000
        if logText.count > maximumCharacters {
            logText.removeFirst(logText.count - maximumCharacters)
        }
    }
}

enum OpenFortiVPNLocator {
    static func executableURL() throws -> URL {
        let helperURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let contentsURL = helperURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundledURL = contentsURL.appendingPathComponent("Resources/openfortivpn")
        if isExecutableFile(bundledURL) {
            return bundledURL.resolvingSymlinksInPath()
        }

        #if FORTIBAR_ALLOW_HOMEBREW
        for path in [
            "/opt/homebrew/bin/openfortivpn",
            "/usr/local/bin/openfortivpn",
            "/opt/local/bin/openfortivpn"
        ] {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            if isExecutableFile(url) { return url }
        }
        throw OpenFortiVPNError.developmentBinaryNotFound
        #else
        throw OpenFortiVPNError.bundledBinaryNotFound
        #endif
    }

    private static func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }
}

enum OpenFortiVPNError: LocalizedError {
    case developmentBinaryNotFound
    case bundledBinaryNotFound

    var errorDescription: String? {
        switch self {
        case .developmentBinaryNotFound:
            "openfortivpn was not found. Install it with Homebrew or bundle it in FortiBar."
        case .bundledBinaryNotFound:
            "This release does not contain openfortivpn. Bundle and sign it before distribution."
        }
    }
}
