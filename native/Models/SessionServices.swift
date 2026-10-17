/// The app-wide pieces a session works with.
struct SessionServices {
    let plugins: PluginRegistry
    let titles: SessionTitles
    /// Hands an event to every plugin, in the order events are posted.
    let post: (SessionEvent) -> Void
    /// Tells the app a session has a title of Native's or the user's now, so the folder made for it
    /// can be named after it.
    let titleLanded: (SessionKey, URL, String) -> Void
}
