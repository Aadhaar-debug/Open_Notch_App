import AudioToolbox
import CoreAudio
import Foundation

/// Reports output volume / mute changes using CoreAudio property listeners (no polling).
final class VolumeService {
    var onChange: ((Float, Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private let queue = DispatchQueue.main
    private var lastLevel: Float = -1
    private var lastMuted = false
    private var listenersInstalled = false

    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.attachToDefaultDevice()
    }
    private lazy var volumeListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.report()
    }

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &Self.defaultDeviceAddress, queue, deviceListener)
        attachToDefaultDevice()
    }

    private func attachToDefaultDevice() {
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, queue, volumeListener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, queue, volumeListener)
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress,
                                   0, nil, &size, &id)
        device = id
        guard id != kAudioObjectUnknown else { return }
        AudioObjectAddPropertyListenerBlock(id, &Self.volumeAddress, queue, volumeListener)
        AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, queue, volumeListener)
        // Remember the current level silently so switching devices doesn't flash a HUD.
        (lastLevel, lastMuted) = read()
    }

    private func read() -> (Float, Bool) {
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &level)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &Self.muteAddress) {
            AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &muted)
        }
        return (level, muted != 0)
    }

    private func report() {
        let (level, muted) = read()
        guard abs(level - lastLevel) > 0.001 || muted != lastMuted else { return }
        lastLevel = level
        lastMuted = muted
        onChange?(level, muted)
    }
}
