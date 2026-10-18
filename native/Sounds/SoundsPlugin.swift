import ACP

/// Plays a sound when a task finishes, needs approval or stops at a limit, through
/// `NotificationSounds` and the user's choices in Settings › Sounds.
struct SoundsPlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "sounds",
        name: "Sounds",
        description: "Plays a sound when a task finishes, needs your approval or reaches a limit."
    )

    let sounds: NotificationSounds

    init(sounds: NotificationSounds = .shared) {
        self.sounds = sounds
    }

    func handle(_ event: SessionEvent) async {
        switch event {
        // A subagent's approval blocks its parent, so it sounds too; its finishing doesn't.
        case .permissionRequested(let session, _):
            await sounds.play(.approvalNeeded, for: session)
        case .turnEnded(let session, let reason) where session.parentID == nil:
            if let trigger = Self.trigger(for: reason) {
                await sounds.play(trigger, for: session)
            }
        default:
            break
        }
    }

    /// Cancelled turns were the user's doing, and errors show in the transcript.
    private static func trigger(for reason: StopReason) -> SoundTrigger? {
        switch reason {
        case .endTurn, .refusal: .taskFinished
        case .maxTokens, .maxTurnRequests: .limitReached
        case .cancelled, .error, .other: nil
        }
    }
}
