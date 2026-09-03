import Foundation
import ServiceManagement

struct HelperInstaller {
    private var service: SMAppService {
        SMAppService.daemon(plistName: FortiBarIPC.daemonPlistName)
    }

    var status: SMAppService.Status { service.status }

    func register() throws {
        if service.status == .enabled { return }
        try service.register()
    }

    func unregister() throws {
        if service.status != .notRegistered {
            try service.unregister()
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

extension SMAppService.Status {
    var fortiBarDescription: String {
        switch self {
        case .notRegistered: "Not installed"
        case .enabled: "Ready"
        case .requiresApproval: "Needs approval"
        case .notFound: "Not installed"
        @unknown default: "Unknown"
        }
    }
}
