import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    enum Issue {
        case requiresApproval
        case registrationFailed
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var issue: Issue?

    init() {
        updateStatus()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            updateStatus()
        } catch {
            updateStatus()
            issue = .registrationFailed
        }
    }

    private func updateStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        issue = status == .requiresApproval ? .requiresApproval : nil
    }
}
