import Foundation
import IOBluetooth

/// Announces Bluetooth device connects / disconnects (AirPods, keyboards, …).
final class BluetoothService: NSObject {
    var onEvent: ((String, Bool) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date()

    func start() {
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        // Registration replays already-connected devices; don't announce those at launch.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        onEvent?(device.name ?? "Bluetooth device", true)
    }

    @objc private func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        onEvent?(device.name ?? "Bluetooth device", false)
    }
}
