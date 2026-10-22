/// The queued message a client is editing. The draft belongs to the client and survives when the
/// message starts or is removed, so unsaved changes can still be sent as a new message.
public struct PromptQueueEdit: Equatable, Sendable {
    public var id: PromptQueue.Item.ID?

    public init(id: PromptQueue.Item.ID? = nil) {
        self.id = id
    }

    /// Reconcile against the visible queue, whether local or received from a host. Clearing the
    /// selection also prevents restoring a removed message from reopening an old edit.
    public mutating func reconcile(with prompts: [PromptQueue.Item]) {
        if let id, !prompts.contains(where: { $0.id == id }) {
            self.id = nil
        }
    }
}
