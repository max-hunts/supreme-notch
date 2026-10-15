//
//  AudioOutputManager.swift
//  Notchly
//
//  Lists audio output devices, switches the system default output, and shows a notice
//  when the output changes. CoreAudio needs no privacy permission for any of this.
//

import AppKit
import Combine
import CoreAudio
import Foundation

nonisolated struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32

    var symbolName: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return AirPodsGlanceManager.deviceSymbol(for: name)
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeUSB:
            return "hifispeaker.fill"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        default:
            return "speaker.wave.2.fill"
        }
    }
}

@MainActor
final class AudioOutputManager: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var defaultDeviceID: AudioDeviceID = 0

    private let settingsManager: SettingsManager
    private let agentEventManager: AgentEventManager
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var defaultListener: AudioObjectPropertyListenerBlock?
    /// When each device first appeared, to skip "now playing on" for AirPods that just connected.
    private var firstSeen: [AudioDeviceID: Date] = [:]
    private var lastAnnouncedID: AudioDeviceID = 0

    init(settingsManager: SettingsManager, agentEventManager: AgentEventManager) {
        self.settingsManager = settingsManager
        self.agentEventManager = agentEventManager
    }

    func start() {
        guard deviceListener == nil else { return }
        refresh(announce: false)
        lastAnnouncedID = defaultDeviceID

        let onDevices: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.refresh(announce: false) }
            }
        }
        let onDefault: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.refresh(announce: true) }
            }
        }
        var devicesAddress = Self.address(kAudioHardwarePropertyDevices)
        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, .main, onDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, onDefault)
        deviceListener = onDevices
        defaultListener = onDefault
    }

    func stop() {
        var devicesAddress = Self.address(kAudioHardwarePropertyDevices)
        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        if let deviceListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, .main, deviceListener)
        }
        if let defaultListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, defaultListener)
        }
        deviceListener = nil
        defaultListener = nil
    }

    func select(_ device: AudioOutputDevice) {
        var id = device.id
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        if status == noErr {
            // Chosen here, so no notice; the panel already shows the checkmark.
            lastAnnouncedID = device.id
            refresh(announce: false)
        }
    }

    private func refresh(announce: Bool) {
        let now = Date()
        let list = Self.outputDevices()
        for device in list where firstSeen[device.id] == nil {
            firstSeen[device.id] = now
        }
        if list != devices {
            devices = list
        }

        let current = Self.defaultOutputID()
        if current != defaultDeviceID {
            defaultDeviceID = current
        }

        guard announce, settingsManager.showAudioOutputGlance, current != lastAnnouncedID,
              let device = list.first(where: { $0.id == current }) else { return }
        lastAnnouncedID = current

        // Headphones that just connected get the AirPods notice with battery rings instead.
        let isBluetooth = device.transport == kAudioDeviceTransportTypeBluetooth || device.transport == kAudioDeviceTransportTypeBluetoothLE
        if isBluetooth, let seen = firstSeen[device.id], now.timeIntervalSince(seen) < 8, settingsManager.showAirPodsGlance {
            return
        }

        agentEventManager.publishGlance(
            source: "audio-output",
            title: "Sound output",
            detail: device.name,
            style: AgentGlanceStyle(symbolName: device.symbolName, red: 0.85, green: 0.85, blue: 0.95),
            actionURL: URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension"),
            ttl: 3
        )
    }

    // MARK: - CoreAudio

    nonisolated private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated static func defaultOutputID() -> AudioDeviceID {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    nonisolated static func outputDevices() -> [AudioOutputDevice] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            // Output-capable: has at least one output stream.
            var streamsAddress = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return nil }

            var hidden: UInt32 = 0
            var hiddenSize = UInt32(MemoryLayout<UInt32>.size)
            var hiddenAddress = Self.address(kAudioDevicePropertyIsHidden)
            if AudioObjectGetPropertyData(id, &hiddenAddress, 0, nil, &hiddenSize, &hidden) == noErr, hidden != 0 { return nil }

            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = Self.address(kAudioObjectPropertyName)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr,
                  let deviceName = name?.takeRetainedValue() as String? else { return nil }

            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = Self.address(kAudioDevicePropertyTransportType)
            AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport)

            return AudioOutputDevice(id: id, name: deviceName, transport: transport)
        }
    }

    #if DEBUG
    /// Sample data for README images.
    func previewLoad(_ devices: [AudioOutputDevice], defaultID: AudioDeviceID) {
        self.devices = devices
        defaultDeviceID = defaultID
    }
    #endif
}
