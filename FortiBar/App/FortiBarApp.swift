import Darwin
import Foundation
import SwiftUI

@main
struct FortiBarApp: App {
    @State private var model: AppModel

    init() {
        guard geteuid() != 0 else {
            FileHandle.standardError.write(Data("FortiBar refuses to run its GUI as root.\n".utf8))
            exit(EXIT_FAILURE)
        }
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .accessibilityLabel("FortiBar, \(model.stateTitle)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
