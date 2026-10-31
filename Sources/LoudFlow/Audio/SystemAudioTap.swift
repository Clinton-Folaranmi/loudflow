import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import OSLog

@available(macOS 14.2, *)
final class SystemAudioTap {

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private let lock = NSLock()

    private var peakValue: Float = 0
    var capturedAnything: Bool {
        lock.lock(); defer { lock.unlock() }
        return peakValue > 0.004
    }

    private var firstHostTime: UInt64?
    var startHostTime: UInt64? {
        lock.lock(); defer { lock.unlock() }
        return firstHostTime
    }

    private static let log = Logger(subsystem: "com.loudflow.app", category: "SystemAudioTap")

    func start(to url: URL) -> Bool {
        do {
            let outputDevice = try Self.defaultOutputDevice()
            let outputUID = try Self.deviceUID(outputDevice)
            let ourProcess = try? Self.processObject(for: getpid())

            let description = CATapDescription(
                stereoGlobalTapButExcludeProcesses: ourProcess.map { [$0] } ?? []
            )
            description.uuid = UUID()
            description.name = "LoudFlow system audio"
            description.isPrivate = true
            description.muteBehavior = CATapMuteBehavior.unmuted

            var tap = AudioObjectID(kAudioObjectUnknown)
            guard AudioHardwareCreateProcessTap(description, &tap) == noErr,
                  tap != AudioObjectID(kAudioObjectUnknown)
            else { return false }
            tapID = tap

            let format = try Self.tapFormat(tap)
            guard let avFormat = Self.audioFormat(from: format) else { throw TapError.badFormat }

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "LoudFlow Capture",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            var aggregate_id = AudioObjectID(kAudioObjectUnknown)
            guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregate_id) == noErr
            else { throw TapError.noAggregateDevice }
            aggregateID = aggregate_id

            file = try AVAudioFile(forWriting: url, settings: avFormat.settings)

            var proc: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate_id, nil) {
                [weak self] _, input, inputTime, _, _ in
                self?.receive(input, at: inputTime.pointee, format: avFormat)
            }
            guard status == noErr, let proc else { throw TapError.noIOProc }
            procID = proc

            guard AudioDeviceStart(aggregate_id, proc) == noErr else { throw TapError.couldNotStart }
            return true
        } catch {
            Self.log.notice("System audio unavailable, continuing mic-only: \(String(describing: error))")
            teardown()
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    private func receive(_ input: UnsafePointer<AudioBufferList>, at time: AudioTimeStamp, format: AVAudioFormat) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input) else { return }
        if time.mFlags.contains(.hostTimeValid) {
            lock.lock()
            if firstHostTime == nil { firstHostTime = time.mHostTime }
            lock.unlock()
        }

        if let channel = buffer.floatChannelData?[0] {
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[i])) }
            lock.lock()
            peakValue = max(peakValue, peak)
            let f = file
            lock.unlock()
            try? f?.write(from: buffer)
        }
    }

    func stop() {
        teardown()
    }

    private func teardown() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown), let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        lock.lock()
        file = nil
        lock.unlock()
    }

    private enum TapError: Error {
        case noDefaultOutput, noDeviceUID, badFormat, noAggregateDevice, noIOProc, couldNotStart
    }

    private static func defaultOutputDevice() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr,
              device != AudioObjectID(kAudioObjectUnknown)
        else { throw TapError.noDefaultOutput }
        return device
    }

    private static func deviceUID(_ device: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw TapError.noDeviceUID }
        return uid as String
    }

    private static func processObject(for pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var input = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &input, &size, &object)
        guard status == noErr else { throw TapError.noDefaultOutput }
        return object
    }

    private static func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd) == noErr
        else { throw TapError.badFormat }
        return asbd
    }

    private static func audioFormat(from asbd: AudioStreamBasicDescription) -> AVAudioFormat? {
        var description = asbd
        return AVAudioFormat(streamDescription: &description)
    }
}
