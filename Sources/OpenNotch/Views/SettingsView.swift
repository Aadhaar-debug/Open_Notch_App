import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Settings.hoverDelay) private var hoverDelay = 0.08
    @AppStorage(Settings.haptics) private var haptics = true
    @AppStorage(Settings.expandOnDrag) private var expandOnDrag = true
    @AppStorage(Settings.showMediaActivity) private var showMediaActivity = true
    @AppStorage(Settings.showVolumeHUD) private var showVolumeHUD = true
    @AppStorage(Settings.showBatteryAlerts) private var showBatteryAlerts = true
    @AppStorage(Settings.showBluetoothAlerts) private var showBluetoothAlerts = true
    @AppStorage(Settings.clipboardHistory) private var clipboardHistory = true
    @AppStorage(Settings.showCalendar) private var showCalendar = true
    @StateObject private var launchAtLogin = StateBox(LoginItem.isEnabled)

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin.value)
                    .onChange(of: launchAtLogin.value) { _, on in
                        LoginItem.setEnabled(on)
                        launchAtLogin.value = LoginItem.isEnabled
                    }
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                Picker("Open on hover after", selection: $hoverDelay) {
                    Text("Instantly").tag(0.0)
                    Text("0.1 s").tag(0.08)
                    Text("0.3 s").tag(0.3)
                    Text("0.6 s").tag(0.6)
                }
                Toggle("Haptic feedback when opening", isOn: $haptics)
                Toggle("Open the shelf when dragging files to the notch", isOn: $expandOnDrag)
            }
            Section("Live activities") {
                Toggle("Now playing", isOn: $showMediaActivity)
                Toggle("Volume", isOn: $showVolumeHUD)
                Toggle("Charging and low battery", isOn: $showBatteryAlerts)
                Toggle("Bluetooth devices", isOn: $showBluetoothAlerts)
            }
            Section("Widgets") {
                Toggle("Calendar on Home", isOn: $showCalendar)
                Toggle("Clipboard history (memory only)", isOn: $clipboardHistory)
            }
            Section {
                HStack {
                    Text("OpenNotch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }
}
