import AVFoundation
import AppAppearance
import Foundation
import ObjectiveC
import UserNotifications
import os

@testable import Native

// If a regression reaches play(), fail without ever sending audio to the hardware.
private let playCalls = OSAllocatedUnfairLock(initialState: 0)
extension AVAudioPlayer {
    @objc fileprivate func silentTestPlay() -> Bool {
        playCalls.withLock { $0 += 1 }
        return false
    }
}

@main
@MainActor
struct SilentAudioRegression {
    static func main() async throws {
        guard
            let original = class_getInstanceMethod(
                AVAudioPlayer.self, #selector(AVAudioPlayer.play as (AVAudioPlayer) -> () -> Bool)),
            let replacement = class_getInstanceMethod(AVAudioPlayer.self, #selector(AVAudioPlayer.silentTestPlay))
        else { fatalError("Missing audio playback interception") }
        method_exchangeImplementations(original, replacement)
        defer { method_exchangeImplementations(original, replacement) }
        precondition(NativeAudioPolicy.isMuted, "Harness must default to muted")
        let sounds = NotificationSounds(preferences: SoundPreferences(defaults: PreviewUserDefaults()))
        sounds.isEnabled = { true }
        sounds.preferences.staysQuietDuringFocus = false
        sounds.preferences.timing = .always
        let played = await sounds.play(.taskFinished)
        precondition(!played, "Muted event must report no playback")
        sounds.preview(.taskFinished)
        let player = SoundPlayer()
        guard let option = sounds.option(for: .taskFinished) else { fatalError("Missing chime") }
        let previewPlayed = await player.play(option, volume: 1)
        precondition(!previewPlayed)
        // File previews must be rejected before trying to open the supplied file, too.
        let file = SoundOption(id: option.id, title: "Fixture", source: .file(URL(filePath: "/missing-fixture.wav")))
        let filePlayed = await player.play(file, volume: 1)
        precondition(!filePlayed)
        precondition(
            Mirror(reflecting: player).children.first { $0.label == "current" }.map {
                Mirror(reflecting: $0.value).children.isEmpty
            } == true, "Mute must prevent player creation")
        let celebration = CelebrationPreviewFixtures.center()
        celebration.setAllAutomatic(true)
        celebration.refresh()
        precondition(celebration.resolution.active != nil, "Celebration fixture must be active")
        let notice = NativeNotification(
            id: "silent-fixture", kind: .turnFinished, agent: "fixture", agentName: "Fixture",
            title: "Fixture finished", body: "Test notification", sound: .done)
        guard let content = UserNotificationPoster.content(for: notice) else { fatalError("Missing content") }
        precondition(content.sound == nil, "System notification must carry no sound")
        try await Task.sleep(for: .milliseconds(100))
        precondition(playCalls.withLock { $0 } == 0, "Audio reached AVAudioPlayer.play")
        print("PASS: event, synthesized/file previews, celebration and notification; zero audio-player calls")
    }
}
