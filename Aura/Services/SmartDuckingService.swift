import Foundation
import CoreAudio
import Observation
import os

@MainActor
@Observable
final class SmartDuckingService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valentinkt.Aura", category: "SmartDucking")

    var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                stopMonitoring()
                isDuckingActive = false
                soundEngine.fadeDucking(to: 1.0, duration: 1.0)
            } else {
                startMonitoring()
            }
        }
    }

    private(set) var isDuckingActive: Bool = false

    private let soundEngine: SoundEngine
    private var stateEvaluationTask: Task<Void, Never>?

    // MediaRemote dynamically loaded
    private typealias MediaRemoteRegisterForNowPlayingNotificationsFunction = @convention(c) (DispatchQueue) -> Void
    private typealias MediaRemoteNowPlayingIsPlayingFunction = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias MediaRemoteNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void

    private let mediaRemoteQueue = DispatchQueue(label: "com.aura.mediaremote", qos: .background)
    private let audioListenerQueue = DispatchQueue(label: "com.aura.smartducking.audio", qos: .background)

    private var mediaRemoteRegisterForNowPlayingNotifications: MediaRemoteRegisterForNowPlayingNotificationsFunction?
    private var mediaRemoteNowPlayingIsPlaying: MediaRemoteNowPlayingIsPlayingFunction?
    private var mediaRemoteNowPlayingInfo: MediaRemoteNowPlayingInfoFunction?
    private var mediaRemoteObservers: [NSObjectProtocol] = []
    private var devicesChangedListener: AudioObjectPropertyListenerBlock?
    private var inputDeviceListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]

    init(soundEngine: SoundEngine) {
        self.soundEngine = soundEngine
        loadMediaRemote()
        startMonitoring()
    }

    private func loadMediaRemote() {
        let bundlePath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: bundlePath) as CFURL) else { return }

        if let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            mediaRemoteRegisterForNowPlayingNotifications = unsafeBitCast(
                pointer,
                to: MediaRemoteRegisterForNowPlayingNotificationsFunction.self
            )
        }

        if let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString) {
            mediaRemoteNowPlayingIsPlaying = unsafeBitCast(
                pointer,
                to: MediaRemoteNowPlayingIsPlayingFunction.self
            )
        }

        if let infoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            mediaRemoteNowPlayingInfo = unsafeBitCast(
                infoPointer,
                to: MediaRemoteNowPlayingInfoFunction.self
            )
        }
    }

    func startMonitoring() {
        stopMonitoring()
        guard isEnabled else { return }
        registerMediaRemoteObservers()
        registerAudioListeners()
        scheduleStateEvaluation()
    }

    private func stopMonitoring() {
        stateEvaluationTask?.cancel()
        stateEvaluationTask = nil

        for observer in mediaRemoteObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        mediaRemoteObservers.removeAll()

        removeAudioListeners()
    }

    private func scheduleStateEvaluation() {
        stateEvaluationTask?.cancel()
        guard isEnabled else { return }

        stateEvaluationTask = Task(priority: .background) { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            await self.evaluateCurrentActivityState()
        }
    }

    private func evaluateCurrentActivityState() async {
        guard isEnabled else { return }

        let micActive = isMicActive()
        let mediaPlaying = await isMediaPlaying()
        let shouldDuck = micActive || mediaPlaying
        guard shouldDuck != isDuckingActive else { return }

        isDuckingActive = shouldDuck

        if shouldDuck {
            logger.debug("Smart ducking activated")
            soundEngine.fadeDucking(to: 0.1, duration: 1.5)
        } else {
            logger.debug("Smart ducking released")
            soundEngine.fadeDucking(to: 1.0, duration: 2.0)
        }
    }

    private func registerMediaRemoteObservers() {
        mediaRemoteRegisterForNowPlayingNotifications?(mediaRemoteQueue)

        let notificationNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ]

        for rawName in notificationNames {
            let observer = NotificationCenter.default.addObserver(
                forName: Notification.Name(rawValue: rawName),
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleStateEvaluation()
                }
            }
            mediaRemoteObservers.append(observer)
        }
    }

    private func registerAudioListeners() {
        var devicesAddress = makeDevicesAddress()

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshInputDeviceListeners()
                self?.scheduleStateEvaluation()
            }
        }

        devicesChangedListener = listener

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            audioListenerQueue,
            listener
        )

        refreshInputDeviceListeners()
    }

    private func removeAudioListeners() {
        if let devicesChangedListener {
            var devicesAddress = makeDevicesAddress()
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddress,
                audioListenerQueue,
                devicesChangedListener
            )
        }
        devicesChangedListener = nil

        for (deviceID, listener) in inputDeviceListeners {
            var runningAddress = makeDeviceRunningAddress()
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &runningAddress,
                audioListenerQueue,
                listener
            )
        }
        inputDeviceListeners.removeAll()
    }

    private func refreshInputDeviceListeners() {
        let currentDeviceIDs = Set(inputDeviceIDs())

        for staleDeviceID in inputDeviceListeners.keys where !currentDeviceIDs.contains(staleDeviceID) {
            if let listener = inputDeviceListeners.removeValue(forKey: staleDeviceID) {
                var runningAddress = makeDeviceRunningAddress()
                AudioObjectRemovePropertyListenerBlock(
                    staleDeviceID,
                    &runningAddress,
                    audioListenerQueue,
                    listener
                )
            }
        }

        for deviceID in currentDeviceIDs where inputDeviceListeners[deviceID] == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.scheduleStateEvaluation()
                }
            }

            inputDeviceListeners[deviceID] = listener
            var runningAddress = makeDeviceRunningAddress()
            AudioObjectAddPropertyListenerBlock(
                deviceID,
                &runningAddress,
                audioListenerQueue,
                listener
            )
        }
    }

    private func isMicActive() -> Bool {
        for deviceID in inputDeviceIDs() {
            var isRunning: UInt32 = 0
            var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
            var isRunningAddress = makeDeviceRunningAddress()

            let result = AudioObjectGetPropertyData(
                deviceID,
                &isRunningAddress,
                0,
                nil,
                &isRunningSize,
                &isRunning
            )

            if result == noErr && isRunning > 0 {
                return true
            }
        }

        return false
    }

    private func inputDeviceIDs() -> [AudioDeviceID] {
        currentAudioDeviceIDs().filter(deviceHasInputStreams)
    }

    private func currentAudioDeviceIDs() -> [AudioDeviceID] {
        var propertySize: UInt32 = 0
        var propertyAddress = makeDevicesAddress()

        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )

        guard result == noErr else { return [] }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        guard result == noErr else { return [] }
        return deviceIDs
    }

    private func deviceHasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var streamSize: UInt32 = 0
        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let result = AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize)
        return result == noErr && streamSize > 0
    }

    private func makeDevicesAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func makeDeviceRunningAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func isMediaPlaying() async -> Bool {
        let isPlayingViaApp = await withCheckedContinuation { continuation in
            guard let checkMedia = mediaRemoteNowPlayingIsPlaying else {
                continuation.resume(returning: false)
                return
            }
            checkMedia(mediaRemoteQueue) { isPlaying in
                continuation.resume(returning: isPlaying)
            }
        }

        if isPlayingViaApp { return true }

        let isPlayingViaInfo = await withCheckedContinuation { continuation in
            guard let getInfo = mediaRemoteNowPlayingInfo else {
                continuation.resume(returning: false)
                return
            }
            getInfo(mediaRemoteQueue) { info in
                var rate: Double = 0.0
                if let info = info {
                    if let r = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
                        rate = r
                    } else if let r = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber {
                        rate = r.doubleValue
                    }
                }
                continuation.resume(returning: rate > 0.0)
            }
        }

        return isPlayingViaInfo
    }
}
