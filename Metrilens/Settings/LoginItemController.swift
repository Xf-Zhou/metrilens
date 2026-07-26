import Foundation
import ServiceManagement

enum LoginItemResult {
    case enabled
    case disabled
    case requiresApproval
    case failed(Error)
}

struct LoginItemController {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) -> LoginItemResult {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                return SMAppService.mainApp.status == .requiresApproval ? .requiresApproval : .enabled
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
                return .disabled
            }
        } catch {
            return .failed(error)
        }
    }
}
