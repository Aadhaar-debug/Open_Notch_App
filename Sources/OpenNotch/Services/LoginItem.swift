import ServiceManagement

/// Registers the app under System Settings › General › Login Items › "Open at Login".
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("OpenNotch: login item change failed: \(error.localizedDescription)")
        }
    }
}
