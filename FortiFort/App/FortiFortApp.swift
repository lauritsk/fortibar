import AppKit
import Darwin
import Foundation
import SwiftUI

@main
struct FortiFortApp: App {
    private let instanceLock: SingleInstanceLock
    @StateObject private var model: AppModel

    init() {
        guard geteuid() != 0 else {
            FileHandle.standardError.write(Data("FortiFort refuses to run its GUI as root.\n".utf8))
            exit(EXIT_FAILURE)
        }
        guard let instanceLock = SingleInstanceLock() else {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: FortiFortIPC.appBundleIdentifier
            )
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
            .activate(options: [])
            exit(EXIT_SUCCESS)
        }
        self.instanceLock = instanceLock
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .accessibilityLabel("FortiFort, \(model.stateTitle)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
