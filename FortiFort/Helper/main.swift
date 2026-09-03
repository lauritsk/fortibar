import Darwin
import Foundation

private var retainedDelegate: HelperListenerDelegate?
private var terminationSources: [DispatchSourceSignal] = []

@MainActor
private func installTerminationHandler(for signalNumber: Int32, runner: VPNRunner) {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        _ = runner.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            exit(EXIT_SUCCESS)
        }
    }
    source.resume()
    terminationSources.append(source)
}

guard geteuid() == 0 else {
    FileHandle.standardError.write(Data("FortiFortHelper must be launched by macOS as root.\n".utf8))
    exit(EXIT_FAILURE)
}

do {
    let runner = VPNRunner()
    let delegate = HelperListenerDelegate(runner: runner)
    retainedDelegate = delegate

    let listener = NSXPCListener(machServiceName: FortiFortIPC.machServiceName)
    let requirement = try CodeSigningRequirement.forPeer(identifier: FortiFortIPC.appBundleIdentifier)
    listener.setConnectionCodeSigningRequirement(requirement)
    listener.delegate = delegate

    installTerminationHandler(for: SIGTERM, runner: runner)
    installTerminationHandler(for: SIGINT, runner: runner)
    listener.activate()
    dispatchMain()
} catch {
    FileHandle.standardError.write(Data("FortiFortHelper failed to start: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
