import ACP

/// Plays a sound for what just happened, through `NotificationSounds` and the user's choices in
/// Settings › Sounds: one sound when a task finishes, another when something needs the user, and a
/// third when something went wrong. This is the only place Native plays sounds for events, so the
/// user never hears two for one moment.
struct SoundsPlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "sounds",
        name: "Sounds",
        description: "Plays a sound when a task finishes, when something needs you, and when something goes wrong."
    )

    let sounds: NotificationSounds

    init(sounds: NotificationSounds = .shared) {
        self.sounds = sounds
    }

    func handle(_ event: SessionEvent) async {
        guard let (trigger, session) = Self.trigger(for: event, isRetrying: sounds.isRetrying) else { return }
        await sounds.play(trigger, for: session)
    }

    /// The sound an event calls for, and the session it's about; nil for events that stay quiet.
    static func trigger(
        for event: SessionEvent,
        isRetrying: (SessionContext) -> Bool
    ) -> (SoundTrigger, SessionContext?)? {
        switch event {
        // A subagent's request blocks its parent, so it sounds too.
        case .permissionRequested(let session, _), .questionAsked(let session, _):
            (.needsYou, session)
        case .needsUser(let session, _):
            (.needsYou, session)
        case .failed(let session, _):
            (.wentWrong, session)
        // A subagent's turn is part of its parent's, which sounds when it ends.
        case .turnEnded(let session, let reason) where session.parentID == nil:
            trigger(for: reason).map { ($0, session) }
        // A dropped connection Native will retry on its own isn't a failure yet.
        case .turnFailed(let session, _, _, _) where session.parentID == nil && !isRetrying(session):
            (.wentWrong, session)
        default:
            nil
        }
    }

    /// A cancelled turn was the user's doing. A refusal or a token or turn limit means the task
    /// didn't get done.
    private static func trigger(for reason: StopReason) -> SoundTrigger? {
        switch reason {
        case .endTurn, .other: .taskFinished
        case .refusal, .maxTokens, .maxTurnRequests, .error: .wentWrong
        case .cancelled: nil
        }
    }
}
