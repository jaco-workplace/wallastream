import AudioToolbox
import CoreAudio
import Foundation
import os

enum CaptureError: LocalizedError {
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .coreAudio(what, status): return "\(what) mislukt (OSStatus \(status))"
        }
    }
}

/// Vangt systeemaudio op via een Core Audio process tap (macOS 14.2+): alles, of alleen bepaalde processen.
/// Geen virtuele audiodriver nodig. Levert interleaved stereo Float32 aan een ringbuffer.
final class SystemAudioCapture {
    let ring = RingBuffer(capacityFrames: 48_000 * 2) // ~2 s bij 48 kHz
    private(set) var sampleRate: Double = 48_000

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var tapDescription: CATapDescription?
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    var isRunning: Bool { ioProcID != nil }

    /// - Parameter processes: `nil` = alle systeemaudio; anders alleen deze Core Audio-procesobjecten.
    ///   Met `muteLocal` zijn alleen de opgevangen processen lokaal stil, de rest speelt gewoon op de Mac.
    func start(processes: [AudioObjectID]?, muteLocal: Bool) throws {
        stop()

        let desc = processes.map { CATapDescription(stereoMixdownOfProcesses: $0) }
            ?? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription = desc
        desc.uuid = UUID()
        desc.name = "Wallastream"
        desc.isPrivate = true
        desc.muteBehavior = muteLocal ? .mutedWhenTapped : .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(desc, &tap), "Tap aanmaken")
        tapID = tap

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &format), "Tap-formaat lezen")
        sampleRate = format.mSampleRate
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = Int(format.mChannelsPerFrame)

        // Aggregate device met de standaard output als klok en de tap als input.
        let outputUID = try defaultOutputDeviceUID()
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Wallastream Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &agg), "Aggregate device aanmaken")
        aggregateID = agg

        let ring = self.ring
        var procID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, inData, _, _, _ in
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard abl.count > 0, let first = abl[0].mData else { return }
            if nonInterleaved, abl.count >= 2, let right = abl[1].mData {
                let frames = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
                ring.writeDeinterleaved(left: first.assumingMemoryBound(to: Float.self),
                                        right: right.assumingMemoryBound(to: Float.self),
                                        frames: frames)
            } else {
                let samples = first.assumingMemoryBound(to: Float.self)
                let frames = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size / max(channels, 1)
                ring.writeInterleaved(samples, frames: frames, channels: channels)
            }
        }, "IOProc aanmaken")
        ioProcID = procID

        try check(AudioDeviceStart(aggregateID, ioProcID), "Opname starten")
    }

    /// Past de lijst opgevangen processen aan zonder de tap opnieuw te maken (bijv. als een browser
    /// een nieuw helper-proces start).
    func updateProcesses(_ processes: [AudioObjectID]) {
        guard let desc = tapDescription, tapID != kAudioObjectUnknown, desc.processes != processes else { return }
        desc.processes = processes
        var ref = desc
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        _ = withUnsafeMutablePointer(to: &ref) {
            AudioObjectSetPropertyData(tapID, &addr, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        tapDescription = nil
        ring.reset()
    }

    private func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID),
                  "Standaard output opvragen")
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        try withUnsafeMutablePointer(to: &uid) {
            try check(AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, $0), "Device-UID opvragen")
        }
        return uid as String
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw CaptureError.coreAudio(what, status) }
    }
}

/// Eenvoudige stereo-ringbuffer (interleaved Float32). Bij overloop worden de oudste samples overschreven.
final class RingBuffer: @unchecked Sendable {
    private let capacity: Int // in frames
    private let buffer: UnsafeMutablePointer<Float>
    private var readPos = 0
    private var writePos = 0
    private var count = 0
    private let lock = OSAllocatedUnfairLock()
    let dataAvailable = DispatchSemaphore(value: 0)

    init(capacityFrames: Int) {
        capacity = capacityFrames
        buffer = .allocate(capacity: capacityFrames * 2)
        buffer.initialize(repeating: 0, count: capacityFrames * 2)
    }

    deinit { buffer.deallocate() }

    func writeInterleaved(_ src: UnsafePointer<Float>, frames: Int, channels: Int) {
        lock.withLockUnchecked {
            for i in 0..<frames {
                let l = src[i * channels]
                let r = channels > 1 ? src[i * channels + 1] : l
                putFrame(l, r)
            }
        }
        dataAvailable.signal()
    }

    func writeDeinterleaved(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int) {
        lock.withLockUnchecked {
            for i in 0..<frames { putFrame(left[i], right[i]) }
        }
        dataAvailable.signal()
    }

    private func putFrame(_ l: Float, _ r: Float) {
        buffer[writePos * 2] = l
        buffer[writePos * 2 + 1] = r
        writePos = (writePos + 1) % capacity
        if count == capacity {
            readPos = (readPos + 1) % capacity
        } else {
            count += 1
        }
    }

    /// Leest maximaal `maxFrames` frames naar `dst` (interleaved). Geeft het aantal gelezen frames terug.
    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        lock.withLockUnchecked {
            let n = min(maxFrames, count)
            for i in 0..<n {
                let p = (readPos + i) % capacity
                dst[i * 2] = buffer[p * 2]
                dst[i * 2 + 1] = buffer[p * 2 + 1]
            }
            readPos = (readPos + n) % capacity
            count -= n
            return n
        }
    }

    func reset() {
        lock.withLockUnchecked { readPos = 0; writePos = 0; count = 0 }
    }
}
