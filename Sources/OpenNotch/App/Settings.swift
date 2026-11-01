import Foundation

/// UserDefaults keys. Views read them with @AppStorage, services with UserDefaults.
enum Settings {
    static let didSetUpLoginItem = "didSetUpLoginItem"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let hoverDelay = "hoverDelay"
    static let haptics = "haptics"
    static let expandOnDrag = "expandOnDrag"
    static let showMediaActivity = "showMediaActivity"
    static let showVolumeHUD = "showVolumeHUD"
    static let showBatteryAlerts = "showBatteryAlerts"
    static let showBluetoothAlerts = "showBluetoothAlerts"
    static let clipboardHistory = "clipboardHistory"
    static let showCalendar = "showCalendar"
    static let focusMinutes = "focusMinutes"
    static let breakMinutes = "breakMinutes"
    static let shelfPaths = "shelfPaths"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showMenuBarIcon: true,
            hoverDelay: 0.08,
            haptics: true,
            expandOnDrag: true,
            showMediaActivity: true,
            showVolumeHUD: true,
            showBatteryAlerts: true,
            showBluetoothAlerts: true,
            clipboardHistory: true,
            showCalendar: true,
            focusMinutes: 25,
            breakMinutes: 5,
        ])
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
}
