import Foundation
import AppKit
import IslandCore
import ScreenCaptureKit
import AVFoundation
import CoreAudio
import CoreGraphics
import CoreMedia
import os

protocol AudioPlaybackDataSource: Sendable {
    func currentState() async -> AudioPlaybackState
}

enum AudioPlaybackDataSourceFactory {
    static func defaultSource(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any AudioPlaybackDataSource {
        let optInValue = environment["ISLAND_REAL_AUDIO_WAVEFORM"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let usesRealCapture = ["1", "true", "yes", "on"].contains(optInValue ?? "")
        let usesCoreAudioTap = ["1", "true", "yes", "on"].contains(
            environment["ISLAND_CORE_AUDIO_TAP_WAVEFORM"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
        )

        if usesCoreAudioTap {
            return CoreAudioProcessTapAudioPlaybackDataSource()
        }

        return usesRealCapture
            ? ScreenCaptureAudioPlaybackDataSource()
            : AppleScriptAudioPlaybackDataSource()
    }
}

final class CoreAudioProcessTapAudioPlaybackDataSource: AudioPlaybackDataSource, @unchecked Sendable {
    private let logger = Logger(subsystem: "cx.island.mvp", category: "audio")
    private let fallback = AppleScriptAudioPlaybackDataSource()
    private let lock = NSLock()
    private let targetBundleIdentifiers = [
        "com.apple.Music",
        "com.spotify.client",
        "com.coppertino.Vox",
        "com.colliderli.iina"
    ]
    private var didAttemptStart = false
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var latestSnapshot = AudioPlaybackSnapshot.idle
    private var latestSampleDate: Date?

    deinit {
        stopTap()
    }

    func currentState() async -> AudioPlaybackState {
        await ensureStarted()

        let current = withLockedState {
            (snapshot: latestSnapshot, sampleDate: latestSampleDate)
        }

        if let sampleDate = current.sampleDate,
           Date().timeIntervalSince(sampleDate) <= 1.5,
           current.snapshot.isWaveformActive {
            return current.snapshot
        }

        return await fallback.currentState()
    }

    private func ensureStarted() async {
        guard #available(macOS 14.2, *) else {
            logger.info("Core Audio process tap unavailable before macOS 14.2")
            return
        }

        let shouldStart = withLockedState {
            guard !didAttemptStart else { return false }
            didAttemptStart = true
            return true
        }

        guard shouldStart else { return }

        await Task.detached(priority: .utility) { [weak self] in
            self?.startTapIfPossible()
        }.value
    }

    @available(macOS 14.2, *)
    private func startTapIfPossible() {
        let processIDs = audioProcessObjectIDsForRunningPlayers()
        guard !processIDs.isEmpty else {
            logger.info("Core Audio process tap skipped: no supported player process object")
            return
        }

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processIDs)
        tapDescription.name = "Island Player Audio Tap"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = CATapMuteBehavior.unmuted

        var createdTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &createdTapID)
        guard status == noErr, createdTapID != kAudioObjectUnknown else {
            logger.error("Core Audio process tap creation failed: \(status, privacy: .public)")
            return
        }

        guard let tapUID = tapUID(for: createdTapID) else {
            logger.error("Core Audio process tap has no UID")
            AudioHardwareDestroyProcessTap(createdTapID)
            return
        }

        var createdAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(
            aggregateDescription(tapUID: tapUID) as CFDictionary,
            &createdAggregateID
        )
        guard status == noErr, createdAggregateID != kAudioObjectUnknown else {
            logger.error("Core Audio aggregate device creation failed: \(status, privacy: .public)")
            AudioHardwareDestroyProcessTap(createdTapID)
            return
        }

        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        var createdIOProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcID(createdAggregateID, islandCoreAudioProcessTapIOProc, unmanagedSelf, &createdIOProcID)
        guard status == noErr, let createdIOProcID else {
            logger.error("Core Audio process tap IOProc creation failed: \(status, privacy: .public)")
            AudioHardwareDestroyAggregateDevice(createdAggregateID)
            AudioHardwareDestroyProcessTap(createdTapID)
            return
        }

        status = AudioDeviceStart(createdAggregateID, createdIOProcID)
        guard status == noErr else {
            logger.error("Core Audio process tap start failed: \(status, privacy: .public)")
            AudioDeviceDestroyIOProcID(createdAggregateID, createdIOProcID)
            AudioHardwareDestroyAggregateDevice(createdAggregateID)
            AudioHardwareDestroyProcessTap(createdTapID)
            return
        }

        withLockedState {
            tapID = createdTapID
            aggregateDeviceID = createdAggregateID
            ioProcID = createdIOProcID
        }
        logger.info("Core Audio process tap started")
    }

    private func stopTap() {
        guard #available(macOS 14.2, *) else {
            return
        }

        let state = withLockedState {
            let state = (tapID: tapID, aggregateDeviceID: aggregateDeviceID, ioProcID: ioProcID)
            tapID = AudioObjectID(kAudioObjectUnknown)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            ioProcID = nil
            return state
        }

        if state.aggregateDeviceID != kAudioObjectUnknown, let ioProcID = state.ioProcID {
            AudioDeviceStop(state.aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(state.aggregateDeviceID, ioProcID)
        }

        if state.aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(state.aggregateDeviceID)
        }

        if state.tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(state.tapID)
        }
    }

    private func audioProcessObjectIDsForRunningPlayers() -> [AudioObjectID] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard
                let bundleIdentifier = application.bundleIdentifier,
                targetBundleIdentifiers.contains(bundleIdentifier)
            else {
                return nil
            }

            return audioProcessObjectID(pid: application.processIdentifier)
        }
    }

    private func audioProcessObjectID(pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processID = pid
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let qualifierSize = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            qualifierSize,
            &processID,
            &dataSize,
            &processObjectID
        )

        guard status == noErr, processObjectID != kAudioObjectUnknown else {
            return nil
        }

        return processObjectID
    }

    @available(macOS 14.2, *)
    private func tapUID(for tapID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(tapID, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        var unmanagedUID: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &unmanagedUID) == noErr,
              let unmanagedUID
        else {
            return nil
        }

        return unmanagedUID.takeRetainedValue() as String
    }

    private func aggregateDescription(tapUID: String) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "Island Player Audio",
            kAudioAggregateDeviceUIDKey: "cx.island.mvp.coreaudio-tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]
    }

    fileprivate func handleAudioBufferList(_ bufferList: UnsafePointer<AudioBufferList>) {
        guard let levels = Self.levels(from: bufferList),
              !levels.isEmpty
        else {
            return
        }

        withLockedState {
            latestSnapshot = AudioPlaybackSnapshot(levels: levels)
            latestSampleDate = Date()
        }
    }

    private static func levels(from bufferList: UnsafePointer<AudioBufferList>, bucketCount: Int = 38) -> [Double]? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        var samples: [Double] = []

        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            guard sampleCount > 0 else { continue }

            let stride = max(1, sampleCount / 768)
            let typedSamples = data.assumingMemoryBound(to: Float32.self)
            var sampleIndex = 0
            while sampleIndex < sampleCount {
                samples.append(Double(typedSamples[sampleIndex]))
                sampleIndex += stride
            }
        }

        guard !samples.isEmpty else { return nil }

        return bucketedLevels(from: samples, bucketCount: bucketCount, gain: 8.5)
    }

    private func withLockedState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func bucketedLevels(from samples: [Double], bucketCount: Int, gain: Double) -> [Double] {
    let bucketSize = max(1, samples.count / bucketCount)
    var levels: [Double] = []
    var start = 0
    while start < samples.count && levels.count < bucketCount {
        let end = min(samples.count, start + bucketSize)
        let slice = samples[start..<end]
        let rms = sqrt(slice.reduce(0.0) { $0 + ($1 * $1) } / Double(max(1, slice.count)))
        let polarity = slice.reduce(0.0, +) >= 0 ? 1.0 : -1.0
        let normalized = min(1, rms * gain) * polarity
        levels.append(normalized)
        start += bucketSize
    }

    return levels
}

private func islandCoreAudioProcessTapIOProc(
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else {
        return noErr
    }

    let dataSource = Unmanaged<CoreAudioProcessTapAudioPlaybackDataSource>
        .fromOpaque(inClientData)
        .takeUnretainedValue()
    dataSource.handleAudioBufferList(inInputData)
    return noErr
}

final class ScreenCaptureAudioPlaybackDataSource: NSObject, AudioPlaybackDataSource, SCStreamOutput, @unchecked Sendable {
    private let logger = Logger(subsystem: "cx.island.mvp", category: "audio")
    private let fallback = AppleScriptAudioPlaybackDataSource()
    private let queue = DispatchQueue(label: "cx.island.audio-capture")
    private let lock = NSLock()
    private var stream: SCStream?
    private var didAttemptStart = false
    private var latestSnapshot = AudioPlaybackSnapshot.idle
    private var latestSampleDate: Date?
    private var didLogFirstSample = false
    private var didLogFallback = false
    private var cachedFallbackState = AudioPlaybackSnapshot.idle
    private var cachedFallbackDate: Date?

    func currentState() async -> AudioPlaybackState {
        await ensureStarted()

        let current = withLockedState {
            (snapshot: latestSnapshot, sampleDate: latestSampleDate)
        }

        if let sampleDate = current.sampleDate,
           Date().timeIntervalSince(sampleDate) <= 1.5,
           current.snapshot.isWaveformActive {
            return current.snapshot
        }

        let fallbackState = await cachedFallbackState()
        if fallbackState.isWaveformActive {
            withLockedState {
                if !didLogFallback {
                    logger.info("screen capture audio unavailable; using player-state fallback waveform")
                    didLogFallback = true
                }
            }
        }
        return fallbackState
    }

    private func cachedFallbackState() async -> AudioPlaybackState {
        let cached = withLockedState {
            (state: cachedFallbackState, date: cachedFallbackDate)
        }

        if let date = cached.date, Date().timeIntervalSince(date) <= 1.0 {
            return cached.state
        }

        let nextState = await fallback.currentState()
        withLockedState {
            cachedFallbackState = nextState
            cachedFallbackDate = Date()
        }
        return nextState
    }

    private func ensureStarted() async {
        let shouldStart = withLockedState {
            guard !didAttemptStart else { return false }
            didAttemptStart = true
            return true
        }

        guard shouldStart else { return }

        do {
            logger.info("starting screen capture audio stream")
            guard Self.ensureScreenCaptureAccess(logger: logger) else {
                logger.error("screen capture permission was not granted")
                return
            }

            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                logger.error("screen capture audio stream could not start: no display available")
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 24_000
            configuration.channelCount = 2

            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(self, type: SCStreamOutputType.audio, sampleHandlerQueue: queue)
            try await stream.startCapture()

            withLockedState {
                self.stream = stream
            }
            logger.info("screen capture audio stream started")
        } catch {
            logger.error("screen capture audio stream failed: \(String(describing: error), privacy: .public)")
            withLockedState {
                latestSnapshot = .idle
                latestSampleDate = nil
            }
        }
    }

    private static func ensureScreenCaptureAccess(logger: Logger) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            logger.info("screen capture permission preflight passed")
            return true
        }

        logger.info("requesting screen capture permission")
        let granted = CGRequestScreenCaptureAccess()
        logger.info("screen capture permission request result: \(granted, privacy: .public)")
        return granted
    }

    private func withLockedState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == SCStreamOutputType.audio else { return }
        guard let levels = Self.levels(from: sampleBuffer), !levels.isEmpty else {
            logger.debug("screen capture audio sample ignored: unable to derive levels")
            return
        }

        lock.lock()
        latestSnapshot = AudioPlaybackSnapshot(levels: levels)
        latestSampleDate = Date()
        let shouldLogFirstSample = !didLogFirstSample
        didLogFirstSample = true
        lock.unlock()

        if shouldLogFirstSample {
            let peak = levels.map { abs($0) }.max() ?? 0
            logger.info("screen capture audio sample received: buckets=\(levels.count), peak=\(peak, privacy: .public)")
        }
    }

    private static func levels(from sampleBuffer: CMSampleBuffer, bucketCount: Int = 38) -> [Double]? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
            streamDescription.mFormatID == kAudioFormatLinearPCM
        else {
            return nil
        }

        let bytesPerFrame = Int(streamDescription.mBytesPerFrame)
        let channelsPerFrame = max(1, Int(streamDescription.mChannelsPerFrame))
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (streamDescription.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let isBigEndian = (streamDescription.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0

        guard bytesPerFrame > 0, bitsPerChannel > 0, !isBigEndian else { return nil }

        var sizeNeeded = 0
        var blockBuffer: CMBlockBuffer?
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr, sizeNeeded > 0 else { return nil }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: sizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let audioBufferList = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        var samples: [Double] = []
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let byteCount = Int(buffer.mDataByteSize)
            let frameCount = byteCount / bytesPerFrame
            guard frameCount > 0 else { continue }

            let stride = max(1, frameCount / 768)
            let raw = data.assumingMemoryBound(to: UInt8.self)
            var frameIndex = 0
            while frameIndex < frameCount {
                var mixedSample = 0.0
                for channelIndex in 0..<channelsPerFrame {
                    mixedSample += sampleValue(
                        raw,
                        frameIndex: frameIndex,
                        channelIndex: channelIndex,
                        bytesPerFrame: bytesPerFrame,
                        bitsPerChannel: bitsPerChannel,
                        isFloat: isFloat,
                        isSignedInteger: isSignedInteger
                    ) ?? 0
                }
                samples.append(mixedSample / Double(channelsPerFrame))
                frameIndex += stride
            }
        }

        guard !samples.isEmpty else { return nil }

        return bucketedLevels(from: samples, bucketCount: bucketCount, gain: 9.5)
    }

    private static func sampleValue(
        _ raw: UnsafePointer<UInt8>,
        frameIndex: Int,
        channelIndex: Int,
        bytesPerFrame: Int,
        bitsPerChannel: Int,
        isFloat: Bool,
        isSignedInteger: Bool
    ) -> Double? {
        let bytesPerSample = max(1, bitsPerChannel / 8)
        let offset = (frameIndex * bytesPerFrame) + (channelIndex * bytesPerSample)
        let samplePointer = raw.advanced(by: offset)

        if isFloat, bitsPerChannel == 32 {
            return Double(samplePointer.withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee })
        }

        if isFloat, bitsPerChannel == 64 {
            return samplePointer.withMemoryRebound(to: Double.self, capacity: 1) { $0.pointee }
        }

        guard isSignedInteger else { return nil }

        switch bitsPerChannel {
        case 16:
            let sample = samplePointer.withMemoryRebound(to: Int16.self, capacity: 1) { $0.pointee }
            return Double(sample) / Double(Int16.max)
        case 24:
            let value = Int32(samplePointer[0])
                | (Int32(samplePointer[1]) << 8)
                | (Int32(samplePointer[2]) << 16)
            let signExtended = (value & 0x800000) == 0 ? value : value | ~0xFFFFFF
            return Double(signExtended) / 8_388_607.0
        case 32:
            let sample = samplePointer.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
            return Double(sample) / Double(Int32.max)
        default:
            return nil
        }
    }
}

final class AppleScriptAudioPlaybackDataSource: AudioPlaybackDataSource, @unchecked Sendable {
    private let players = [
        ScriptableAudioPlayer(appName: "Music", bundleIdentifier: "com.apple.Music"),
        ScriptableAudioPlayer(appName: "Spotify", bundleIdentifier: "com.spotify.client"),
        ScriptableAudioPlayer(appName: "Vox", bundleIdentifier: "com.coppertino.Vox"),
        ScriptableAudioPlayer(appName: "IINA", bundleIdentifier: "com.colliderli.iina")
    ]
    private let lock = NSLock()
    private var cachedState = AudioPlaybackSnapshot.idle
    private var cachedDate: Date?

    init() {}

    func currentState() async -> AudioPlaybackState {
        let cached = withLockedState {
            (state: cachedState, date: cachedDate)
        }

        if let date = cached.date, Date().timeIntervalSince(date) <= 1.0 {
            return cached.state
        }

        let players = players
        let nextState = await Task.detached(priority: .utility) {
            for player in players
            where Self.isPlayerRunning(bundleIdentifier: player.bundleIdentifier)
                && Self.isPlaying(appName: player.appName) {
                return Self.syntheticPlaybackSnapshot()
            }
            return AudioPlaybackSnapshot.defaultFallback
        }.value

        withLockedState {
            cachedState = nextState
            cachedDate = Date()
        }
        return nextState
    }

    private func withLockedState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func syntheticPlaybackSnapshot() -> AudioPlaybackSnapshot {
        let levels = (0..<38).map { index -> Double in
            let progress = Double(index) / 37.0
            let envelope = 0.28 + (sin(progress * .pi) * 0.26)
            let carrier = sin((progress * .pi * 7.0) + 0.4)
            let texture = sin((progress * .pi * 19.0) - 0.8) * 0.26
            return (carrier + texture) * envelope
        }
        return AudioPlaybackSnapshot(levels: levels)
    }

    private static func isPlayerRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == bundleIdentifier
        }
    }

    private static func isPlaying(appName: String) -> Bool {
        let escapedAppName = appName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        if application "\(escapedAppName)" is running then
            tell application "\(escapedAppName)"
                try
                    if player state is playing then return "playing"
                end try
            end tell
        end if
        return "idle"
        """

        var errorInfo: NSDictionary?
        guard
            let appleScript = NSAppleScript(source: script),
            let output = appleScript.executeAndReturnError(&errorInfo).stringValue
        else {
            return false
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "playing"
    }
}

private struct ScriptableAudioPlayer: Sendable {
    let appName: String
    let bundleIdentifier: String
}
