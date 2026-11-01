import Foundation

/// Owns every long-lived service and wires their events into the notch HUD.
/// Everything here is event driven (notifications / property listeners); the only
/// periodic work is the clipboard check (2 Hz) and the focus timer while it runs.
final class Services {
    static let shared = Services()

    let model = NotchModel()
    let media = MediaService()
    let shelf = ShelfStore()
    let clipboard = ClipboardService()
    let focus = FocusTimer()
    let calendar = CalendarService()
    let stats = SystemStats()
    let volume = VolumeService()
    let battery = BatteryService()
    let bluetooth = BluetoothService()

    func start() {
        media.start()
        clipboard.start()

        volume.onChange = { [weak self] level, muted in
            guard let self, Settings.bool(Settings.showVolumeHUD), !self.model.isExpanded else { return }
            self.model.show(.volume(level: level, muted: muted), for: 1.5)
        }
        volume.start()

        battery.onPowerSourceChange = { [weak self] level, charging in
            guard let self, Settings.bool(Settings.showBatteryAlerts) else { return }
            self.model.show(.battery(level: level, charging: charging), for: 2.5)
        }
        battery.onLowBattery = { [weak self] level in
            guard let self, Settings.bool(Settings.showBatteryAlerts) else { return }
            self.model.show(.lowBattery(level: level), for: 4)
        }
        battery.start()

        bluetooth.onEvent = { [weak self] name, connected in
            guard let self, Settings.bool(Settings.showBluetoothAlerts) else { return }
            self.model.show(.bluetooth(name: name, connected: connected), for: 2.5)
        }
        bluetooth.start()

        focus.onPhaseFinished = { [weak self] nowOnBreak in
            self?.model.show(.focusDone(onBreak: nowOnBreak), for: 4)
        }
    }
}
