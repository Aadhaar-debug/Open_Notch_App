import Foundation
import IOKit.ps

/// Power-source changes from IOKit's run-loop notification (no polling).
final class BatteryService {
    var onPowerSourceChange: ((Int, Bool) -> Void)?
    var onLowBattery: ((Int) -> Void)?

    private var source: CFRunLoopSource?
    private var lastOnAC: Bool?
    private var warnedAt: Int?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue().update()
        }, context)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        update(initial: true)
    }

    private func read() -> (level: Int, onAC: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let level = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let onAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (level, onAC)
        }
        return nil
    }

    private func update(initial: Bool = false) {
        guard let (level, onAC) = read() else { return }
        if !initial, let last = lastOnAC, last != onAC {
            onPowerSourceChange?(level, onAC)
        }
        lastOnAC = onAC

        if onAC { warnedAt = nil; return }
        // Warn once each time the level crosses 20%, 10% and 5%.
        guard let threshold = [5, 10, 20].first(where: { level <= $0 }) else { return }
        if warnedAt == nil || warnedAt! > threshold {
            warnedAt = threshold
            if !initial || level <= 10 { onLowBattery?(level) }
        }
    }
}
