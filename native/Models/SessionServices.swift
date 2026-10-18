import Foundation

/// The app-wide pieces a session works with.
struct SessionServices {
    let plugins: PluginRegistry
    let titles: SessionTitles
    /// What stops every session of an agent from taking messages (sign-in, usage limit).
    let sendGate: AgentSendGate
    /// Hands an event to every plugin, in the order events are posted.
    let post: (SessionEvent) -> Void
    /// Tells the app a session has a title of Native's or the user's now, so the folder made for it
    /// can be named after it.
    let titleLanded: (SessionKey, URL, String) -> Void
}
