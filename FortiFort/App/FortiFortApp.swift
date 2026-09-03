import Darwin
import Foundation
import SwiftUI

@main
struct FortiFortApp: App {
    @StateObject private var model: AppModel

    init() {
        guard geteuid() != 0 else {
            FileHandle.standardError.write(Data("FortiFort refuses to run its GUI as root.\n".utf8))
            exit(EXIT_FAILURE)
        }
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Image(systemName: model.symbolName)
                .accessibilityLabel("FortiFort, \(model.stateTitle)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
