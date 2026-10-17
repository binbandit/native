/// The app-wide pieces a session works with.
struct SessionServices {
    let plugins: PluginRegistry
    let titles: SessionTitles
    /// Hands an event to every plugin, in the order events are posted.
    let post: (SessionEvent) -> Void
}
