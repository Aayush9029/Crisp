import CoreAudio
import Observation
import os

// C function pointer callback for CoreAudio property listener
private func audioPropertyListenerCallback(
    _ objectID: AudioObjectID,
    _ numberAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let manager = Unmanaged<AudioInputManager>.fromOpaque(clientData).takeUnretainedValue()
    Task { @MainActor in
        manager.refreshDevices()
    }
    return noErr
}

@MainActor
@Observable
final class AudioInputManager {
    struct InputDevice: Identifiable, Equatable, Sendable {
        let id: AudioDeviceID
        let name: String
    }

    var inputDevices: [InputDevice] = []
    var forcedDeviceID: AudioDeviceID?
    var isPaused = false
    var isForcing = false

    private let logger = Logger(subsystem: "com.aayush.crisp", category: "AudioInput")

    var forcedDeviceName: String? {
        guard let id = forcedDeviceID else { return nil }
        return inputDevices.first { $0.id == id }?.name
    }

    init() {
        loadSavedDevice()
        refreshDevices()
        registerListeners()
    }

    func selectDevice(_ device: InputDevice) {
        logger.info("Selected: \(device.name) (\(device.id))")
        forcedDeviceID = device.id
        UserDefaults.standard.set(Int(device.id), forKey: "forcedDeviceID")
        forceDefaultInput()
    }

    func togglePause() {
        isPaused.toggle()
        logger.info("Paused: \(self.isPaused)")
        if !isPaused { forceDefaultInput() }
    }

    func refreshDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else {
            logger.error("Cannot get device list size")
            return
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else {
            logger.error("Cannot get device list")
            return
        }

        logger.info("Enumerating \(count) audio devices")
        var devices: [InputDevice] = []

        for deviceID in ids {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(
                deviceID, &streamAddr, 0, nil, &streamSize
            ) == noErr, streamSize > 0 else { continue }

            guard let name = deviceName(for: deviceID) else { continue }
            logger.info("Input device: \(name) (\(deviceID))")
            devices.append(InputDevice(id: deviceID, name: name))

            if name.lowercased().contains("built") && forcedDeviceID == nil {
                forcedDeviceID = deviceID
                logger.info("Auto-selected: \(name)")
            }
        }

        inputDevices = devices

        if let forced = forcedDeviceID, !devices.contains(where: { $0.id == forced }) {
            logger.warning("Forced device disconnected")
            forcedDeviceID = nil
        }

        forceDefaultInput()
    }

    // MARK: - Private

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID, &nameAddr, 0, nil, &nameSize
        ) == noErr, nameSize > 0 else { return nil }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(nameSize), alignment: MemoryLayout<CFString>.alignment)
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceID, &nameAddr, 0, nil, &nameSize, buffer
        ) == noErr else { return nil }

        let cfStr = Unmanaged<CFString>.fromOpaque(buffer.load(as: UnsafeRawPointer.self)).takeUnretainedValue()
        return cfStr as String
    }

    private func loadSavedDevice() {
        let saved = UserDefaults.standard.integer(forKey: "forcedDeviceID")
        if saved != 0 {
            forcedDeviceID = AudioDeviceID(saved)
            logger.info("Loaded saved device: \(saved)")
        }
    }

    private func forceDefaultInput() {
        guard !isPaused, let targetID = forcedDeviceID else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var currentID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &currentID
        )

        guard currentID != targetID else { return }

        logger.info("Forcing input: \(currentID) → \(targetID)")
        isForcing = true

        var mutableID = targetID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID
        )

        if status != noErr {
            logger.error("Force failed: \(status)")
        }

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            isForcing = false
        }

        // Restore max sample rate on default output device after codec switch settles
        Task {
            try? await Task.sleep(for: .seconds(10))
            restoreOutputSampleRate()
        }
    }

    private func restoreOutputSampleRate() {
        var outputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var outputID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &outputAddr, 0, nil, &size, &outputID
        ) == noErr, outputID != 0 else { return }

        // Get available sample rates
        var ratesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var ratesSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            outputID, &ratesAddr, 0, nil, &ratesSize
        ) == noErr, ratesSize > 0 else { return }

        let rateCount = Int(ratesSize) / MemoryLayout<AudioValueRange>.size
        var rates = [AudioValueRange](repeating: AudioValueRange(), count: rateCount)
        guard AudioObjectGetPropertyData(
            outputID, &ratesAddr, 0, nil, &ratesSize, &rates
        ) == noErr else { return }

        guard let maxRate = rates.map(\.mMaximum).max() else { return }

        // Set to max sample rate
        var sampleRateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var currentRate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(outputID, &sampleRateAddr, 0, nil, &rateSize, &currentRate)

        if currentRate < maxRate {
            var newRate = maxRate
            let status = AudioObjectSetPropertyData(
                outputID, &sampleRateAddr, 0, nil,
                UInt32(MemoryLayout<Float64>.size), &newRate
            )
            if status == noErr {
                logger.info("Restored output sample rate: \(currentRate) → \(maxRate)")
            }
        }
    }

    private nonisolated func registerListeners() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &inputAddr,
            audioPropertyListenerCallback,
            selfPtr
        )

        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            audioPropertyListenerCallback,
            selfPtr
        )
    }
}
