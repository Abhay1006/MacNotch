import Foundation
import CoreAudio
import AudioToolbox
import Combine

/// System output volume via CoreAudio.
///
/// This replaces the old `NSAppleScript` round trip (`"output volume of (get volume settings)"`),
/// which was slow, ran on a 10-second poll, and needed Automation permission. CoreAudio is
/// instant, permission-free, and — more importantly — pushes change notifications, so there is
/// nothing to poll at all.
final class AudioManager: ObservableObject {
    @Published private(set) var volume: Int = 50
    @Published private(set) var isMuted: Bool = false

    /// Effective level for display: a muted device reads as 0 regardless of its stored scalar.
    var displayVolume: Int { isMuted ? 0 : volume }

    private var deviceID: AudioDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var registered: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private let listenerQueue = DispatchQueue(label: "com.abhay.MacNotch.audio")

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        attachToDefaultDevice()
        observeDefaultDeviceChanges()
    }

    deinit {
        removeDeviceListeners()
        var address = AudioManager.defaultDeviceAddress
        AudioObjectRemovePropertyListenerBlock(AudioManager.systemObject, &address, listenerQueue, defaultDeviceChanged)
    }

    // MARK: - Public control

    func setVolume(_ newValue: Int) {
        let clamped = max(0, min(100, newValue))
        // Update immediately so the slider tracks the drag without waiting for the
        // CoreAudio notification to come back around.
        volume = clamped
        if isMuted && clamped > 0 { setMuted(false) }

        let scalar = Float32(clamped) / 100.0
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }

        // Some devices expose a single main volume; others only per-channel. Try main
        // first, then fall back to the stereo pair.
        if !writeScalar(scalar, element: kAudioObjectPropertyElementMain) {
            _ = writeScalar(scalar, element: 1)
            _ = writeScalar(scalar, element: 2)
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    func toggleMute() { setMuted(!isMuted) }

    // MARK: - Device wiring

    private func observeDefaultDeviceChanges() {
        var address = AudioManager.defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(AudioManager.systemObject, &address, listenerQueue, defaultDeviceChanged)
    }

    private lazy var defaultDeviceChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        // Headphones plugged in, AirPlay switched, dock connected — rebind to the new device.
        DispatchQueue.main.async { self?.attachToDefaultDevice() }
    }

    private lazy var devicePropertyChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.refresh() }
    }

    private func attachToDefaultDevice() {
        removeDeviceListeners()

        var address = AudioManager.defaultDeviceAddress
        var newDevice = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioManager.systemObject, &address, 0, nil, &size, &newDevice)
        guard status == noErr else {
            Log.system.error("CoreAudio: no default output device (status \(status))")
            return
        }

        deviceID = newDevice
        addDeviceListener(selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain)
        addDeviceListener(selector: kAudioDevicePropertyVolumeScalar, element: 1)
        addDeviceListener(selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
        refresh()
    }

    private func addDeviceListener(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return }
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, listenerQueue, devicePropertyChanged)
        if status == noErr { registered.append((deviceID, address)) }
    }

    private func removeDeviceListeners() {
        for (object, address) in registered {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, listenerQueue, devicePropertyChanged)
        }
        registered.removeAll()
    }

    // MARK: - Reading

    /// Pull the current level from the device. Called on attach and whenever CoreAudio
    /// reports a change — including changes made with the keyboard media keys.
    func refresh() {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }

        if let scalar = readScalar(element: kAudioObjectPropertyElementMain) ?? readScalar(element: 1) {
            volume = Int((scalar * 100).rounded())
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &value) == noErr {
                isMuted = value != 0
            }
        }
    }

    private func readScalar(element: AudioObjectPropertyElement) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    private func writeScalar(_ value: Float32, element: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, settable.boolValue else {
            return false
        }

        var scalar = value
        return AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar
        ) == noErr
    }
}
