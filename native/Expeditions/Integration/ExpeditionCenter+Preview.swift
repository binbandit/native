#if NATIVE_PREVIEWS_WIP
import NativeExpeditions

extension ExpeditionCenter {
    /// A center with no expeditions that keeps nothing (no store, no documents) and has no host, so
    /// nothing it's asked to do can start an agent or make a worktree.
    static func preview() -> ExpeditionCenter {
        ExpeditionCenter(runner: ExpeditionRunner(store: nil, documents: nil))
    }
}
#endif
