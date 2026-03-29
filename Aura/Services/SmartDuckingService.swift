import Foundation
import CoreAudio
import Observation
import os

@MainActor
@Observable
final class SmartDuckingService {
    var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                isDuckingActive = false
                soundEngine.fadeDucking(to: 1.0, duration: 1.0)
            }
        }
    }
    
    private(set) var isDuckingActive: Bool = false
    
    private let soundEngine: SoundEngine
    private var monitoringTask: Task<Void, Never>?
    
    // MediaRemote dynamically loaded
    private typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    
    private var MRMediaRemoteGetNowPlayingApplicationIsPlaying: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction?
    private var MRMediaRemoteGetNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction?
    
    init(soundEngine: SoundEngine) {
        self.soundEngine = soundEngine
        loadMediaRemote()
        startMonitoring()
    }
    
    private func loadMediaRemote() {
        let bundlePath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: bundlePath) as CFURL) else { return }
        
        if let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString) {
            MRMediaRemoteGetNowPlayingApplicationIsPlaying = unsafeBitCast(
                pointer,
                to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction.self
            )
        }
        
        if let infoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(
                infoPointer,
                to: MRMediaRemoteGetNowPlayingInfoFunction.self
            )
        }
    }
    
    func startMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isEnabled else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                
                let micActive = self.isMicActive()
                let mediaPlaying = await self.isMediaPlaying()
                
                let shouldDuck = micActive || mediaPlaying
                
                if shouldDuck && !self.isDuckingActive {
                    self.isDuckingActive = true
                    print("🟢 [SmartDucking] Activity detected, fading out...")
                    self.soundEngine.fadeDucking(to: 0.1, duration: 1.5)
                } else if !shouldDuck && self.isDuckingActive {
                    self.isDuckingActive = false
                    print("🟢 [SmartDucking] Activity ended, fading in...")
                    self.soundEngine.fadeDucking(to: 1.0, duration: 2.0)
                }
                
                // Check every 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
    
    private func isMicActive() -> Bool {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard result == noErr else { return false }
        
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
        
        guard result == noErr else { return false }
        
        for deviceID in deviceIDs {
            // Check if device has input streams
            var streamSize: UInt32 = 0
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            result = AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize)
            guard result == noErr && streamSize > 0 else { continue }
            
            var isRunning: UInt32 = 0
            var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
            var isRunningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            result = AudioObjectGetPropertyData(
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
    
    private func isMediaPlaying() async -> Bool {
        let isPlayingViaApp = await withCheckedContinuation { continuation in
            guard let checkMedia = MRMediaRemoteGetNowPlayingApplicationIsPlaying else {
                continuation.resume(returning: false)
                return
            }
            checkMedia(DispatchQueue.global(qos: .background)) { isPlaying in
                continuation.resume(returning: isPlaying)
            }
        }
        
        if isPlayingViaApp { return true }
        
        let isPlayingViaInfo = await withCheckedContinuation { continuation in
            guard let getInfo = MRMediaRemoteGetNowPlayingInfo else {
                continuation.resume(returning: false)
                return
            }
            getInfo(DispatchQueue.global(qos: .background)) { info in
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
