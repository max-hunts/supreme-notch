//
//  MicMuteManager.swift
//  Notchly
//
//  Mutes every microphone system-wide through CoreAudio. No permission is needed.
//
//  Every input with a mute switch gets it turned on, and it is turned on again whenever
//  something turns it off or an app starts recording. The input level is left alone on
//  those mics: measured on the MacBook Pro microphone, writing a level of zero after
//  muting could let sound through while the switch still read "muted". Inputs without a
//  mute switch get their level set to zero instead, and restored on unmute.
//
//  Inputs with neither control cannot be muted from outside; they are listed in
//  `unmutableInputs` so the button can say so.
//

import Combine
import CoreAudio
import Foundation

@MainActor
final class MicMuteManager: ObservableObject {
    @Published private(set) var isMuted = false
    @Published private(set) var hasInput = false
    /// Names of inputs with no mute switch or input level, which cannot be silenced.
    @Published private(set) var unmutableInputs: [String] = []

    private var wantsMute = false
    /// Input levels before muting, restored on unmute.
    private var savedVolumes: [AudioDeviceID: Float32] = [:]
    private var watchedDevices: [AudioDeviceID: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)]] = [:]
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var enforceTask: Task<Void, Never>?

    func start() {
        guard systemListeners.isEmpty else { return }
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.devicesChanged() }
                }
            }
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            systemListeners.append((address, block))
        }
        devicesChanged()
    }

    func toggle() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        wantsMute = muted
        if muted {
            enforce()
            startEnforcing()
        } else {
            stopEnforcing()
            for device in Self.inputDevices() {
                Self.setMute(false, on: device)
                if let saved = savedVolumes[device] {
                    Self.setInputVolume(saved, on: device)
                }
            }
            savedVolumes.removeAll()
        }
        refresh()
    }

    // MARK: - State

    private func devicesChanged() {
        let devices = Self.inputDevices()
        hasInput = !devices.isEmpty
        unmutableInputs = devices.filter { !Self.canSilence($0) }.map(Self.name)
        watch(devices)
        if wantsMute { enforce() }
        refresh()
    }

    /// Muted means every input that can be silenced is silent.
    private func refresh() {
        let controllable = Self.inputDevices().filter(Self.canSilence)
        let muted = wantsMute && !controllable.isEmpty && controllable.allSatisfy(Self.isSilent)
        if muted != isMuted { isMuted = muted }
    }

    private func enforce(force: Bool = false) {
        for device in Self.inputDevices() {
            Self.silence(device, force: force, saving: &savedVolumes)
        }
    }

    /// Mute switch when there is one; input level zero only when there is not.
    /// `force` toggles the switch off and on, so the driver applies it even if the
    /// property already reads "muted".
    private static func silence(_ device: AudioDeviceID, force: Bool, saving savedVolumes: inout [AudioDeviceID: Float32]) {
        if isSettable(device, kAudioDevicePropertyMute) {
            if force || !isMuteOn(device) {
                if force { setMute(false, on: device) }
                setMute(true, on: device)
            }
        } else if isSettable(device, kAudioDevicePropertyVolumeScalar) {
            if savedVolumes[device] == nil, let volume = inputVolume(device), volume > 0 {
                savedVolumes[device] = volume
            }
            if (inputVolume(device) ?? 0) != 0 { setInputVolume(0, on: device) }
        }
    }

    /// Re-applies the mute every half second as a backstop for changes no listener reports.
    private func startEnforcing() {
        guard enforceTask == nil else { return }
        enforceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.wantsMute else { return }
                if !Self.inputDevices().filter(Self.canSilence).allSatisfy(Self.isSilent) {
                    self.enforce()
                }
                self.refresh()
            }
        }
    }

    private func stopEnforcing() {
        enforceTask?.cancel()
        enforceTask = nil
    }

    /// Listens for mute and level changes on each input, so an app turning the mic back
    /// up is undone straight away.
    private func watch(_ devices: [AudioDeviceID]) {
        for (device, listeners) in watchedDevices where !devices.contains(device) {
            for (address, block) in listeners {
                var address = address
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
            }
            watchedDevices[device] = nil
        }
        for device in devices where watchedDevices[device] == nil {
            var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
            let watched: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
                (kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput),
                (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput),
                (kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal)
            ]
            for (selector, scope) in watched {
                var address = Self.address(selector, scope: scope)
                guard AudioObjectHasProperty(device, &address) else { continue }
                let isRunningChange = selector == kAudioDevicePropertyDeviceIsRunningSomewhere
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            if self.wantsMute {
                                // An app starting to record gets a freshly applied mute.
                                Self.silence(device, force: isRunningChange && Self.isRunning(device), saving: &self.savedVolumes)
                            }
                            self.refresh()
                        }
                    }
                }
                AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
                listeners.append((address, block))
            }
            watchedDevices[device] = listeners
        }
    }

    // MARK: - CoreAudio

    nonisolated private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated static func inputDevices() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var streams = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    nonisolated static func name(_ device: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = address(kAudioObjectPropertyName)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() as String? else { return "Microphone" }
        return value
    }

    nonisolated private static func isSettable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = address(selector, scope: kAudioObjectPropertyScopeInput)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr
            && settable.boolValue
    }

    nonisolated static func canSilence(_ device: AudioDeviceID) -> Bool {
        isSettable(device, kAudioDevicePropertyMute) || isSettable(device, kAudioDevicePropertyVolumeScalar)
    }

    /// Silent when its mute switch is on, or, without one, when its input level is zero.
    nonisolated static func isSilent(_ device: AudioDeviceID) -> Bool {
        if isSettable(device, kAudioDevicePropertyMute) { return isMuteOn(device) }
        return (inputVolume(device) ?? 0) == 0
    }

    nonisolated private static func isRunning(_ device: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    nonisolated private static func isMuteOn(_ device: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    nonisolated private static func setMute(_ muted: Bool, on device: AudioDeviceID) {
        guard isSettable(device, kAudioDevicePropertyMute) else { return }
        var address = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    nonisolated private static func inputVolume(_ device: AudioDeviceID) -> Float32? {
        var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    nonisolated private static func setInputVolume(_ volume: Float32, on device: AudioDeviceID) {
        guard isSettable(device, kAudioDevicePropertyVolumeScalar) else { return }
        var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        var value = volume
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
}
