import AVFoundation
import Foundation

actor AssetManager {
    private var bufferCache: [String: AVAudioPCMBuffer] = [:]

    func loadAudioBuffer(named name: String) async -> AVAudioPCMBuffer? {
        if let cached = bufferCache[name] {
            return cached
        }

        let buffer = await Task.detached(priority: .userInitiated) {
            Self.loadBufferFromDisk(named: name)
        }.value

        if let buffer {
            bufferCache[name] = buffer
        }
        return buffer
    }

    private static func loadBufferFromDisk(named name: String) -> AVAudioPCMBuffer? {
        let bundle = Bundle.main
        let url: URL? =
            bundle.url(forResource: name, withExtension: "m4a", subdirectory: "Resources/Audio") ??
            bundle.url(forResource: name, withExtension: "m4a", subdirectory: "Audio") ??
            bundle.url(forResource: name, withExtension: "m4a") ?? {
                let absolutePath = "/Users/valentin/XCode/Aura/Aura/Resources/Audio/\(name).m4a"
                return FileManager.default.fileExists(atPath: absolutePath) ? URL(fileURLWithPath: absolutePath) : nil
            }()
        
        if let url {
            print("🟢 [AssetManager] Loading audio buffer for \(name) from \(url.path)")
            do {
                // Check file size to avoid AVFoundation logging error for empty files
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                if fileSize > 0 {
                    let file = try AVAudioFile(forReading: url)
                    let format = file.processingFormat
                    let frameCount = AVAudioFrameCount(file.length)
                    if let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
                        try file.read(into: pcm)
                        return pcm
                    }
                } else {
                    return makeSilentBuffer()
                }
            } catch {
                print("🟥 [AssetManager] Error loading buffer for \(name): \(error.localizedDescription)")
                return makeSilentBuffer()
            }
        }
        
        // Return silent buffer if file not found
        return makeSilentBuffer()
    }

    private static func makeSilentBuffer() -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frameCount: AVAudioFrameCount = 44100
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        // PCM buffer is zeroed by default
        return buffer
    }
}

