import Foundation

/// Messages the user sent while the agent was busy. They go out one per turn, in order, as turns
/// end; a cancelled or failed turn pauses them until the user sends again.
nonisolated struct PromptQueue: Equatable, Sendable {
    struct Item: Identifiable, Hashable, Sendable {
        let id: UUID
        var text: String
        /// Whether the message shows in the transcript when it goes out. Messages other sessions
        /// send through Native's tools don't; the transcript records them as session messages.
        let isEchoed: Bool

        init(_ text: String, isEchoed: Bool = true) {
            id = UUID()
            self.text = text
            self.isEchoed = isEchoed
        }
    }

    private(set) var items: [Item] = []
    private(set) var isPaused = false

    var isEmpty: Bool {
        items.isEmpty
    }

    mutating func append(_ text: String, isEchoed: Bool = true) {
        items.append(Item(text, isEchoed: isEchoed))
    }

    /// For a message that should go out before everything already waiting, such as one that
    /// arrived too late to steer the turn it was meant for.
    mutating func prepend(_ text: String, isEchoed: Bool = true) {
        items.insert(Item(text, isEchoed: isEchoed), at: 0)
    }

    /// Edits a message; emptying it removes it.
    mutating func update(_ id: Item.ID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.remove(at: index)
        } else {
            items[index].text = text
        }
    }

    /// Puts a removed message back where it was, for undo.
    mutating func restore(_ item: Item, at index: Int) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.insert(item, at: min(index, items.count))
    }

    func index(of id: Item.ID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    @discardableResult
    mutating func remove(_ id: Item.ID) -> Item? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// The next message to send when a turn ends normally, unless the queue is paused.
    mutating func next() -> Item? {
        guard !isPaused, !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    mutating func pause() {
        isPaused = true
    }

    mutating func resume() {
        isPaused = false
    }
}
