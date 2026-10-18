import AVFoundation
import os

/// Plays one sound at a time; a new one cuts off the last, so a burst of events never stacks up.
final class SoundPlayer {
    /// Files play at half gain at the default volume, the level Native's own sounds are tuned to
    /// match (`ChimeSynthesizer.loudness`), so switching between a file and a built-in sound never
    /// jumps in level.
    static let fileGain = 0.5 / SoundPreferences.defaultVolume

    private var current: AVAudioPlayer?
    /// Each Native sound is synthesized once, on first use, and kept as WAV data.
    private var rendered: [NativeChime: Data] = [:]
    private let logger = Logger(subsystem: "Native", category: "Sounds")

    func play(_ option: SoundOption, volume: Double) async {
        let player: AVAudioPlayer
        do {
            switch option.source {
            case .synthesized(let chime):
                player = try AVAudioPlayer(data: await data(for: chime), fileTypeHint: AVFileType.wav.rawValue)
                player.volume = Float(volume)
            case .file(let url):
                player = try AVAudioPlayer(contentsOf: url)
                player.volume = Float(min(volume * Self.fileGain, 1))
            }
        } catch {
            logger.error(
                "Couldn't play \(option.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        current?.stop()
        current = player
        player.play()
    }

    /// Renders a Native sound ahead of time, so the first notification plays without a delay.
    func prepare(_ chime: NativeChime) async {
        _ = await data(for: chime)
    }

    private func data(for chime: NativeChime) async -> Data {
        if let data = rendered[chime] {
            return data
        }
        let data = await Self.render(chime)
        rendered[chime] = data
        return data
    }

    /// Synthesis takes a few tens of milliseconds, so it runs off the main actor.
    @concurrent
    private nonisolated static func render(_ chime: NativeChime) async -> Data {
        chime.render().wavData
    }
}
