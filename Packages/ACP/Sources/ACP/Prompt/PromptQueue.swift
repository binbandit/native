import Foundation

/// Messages the user sent while the agent was busy. They go out one per turn, in order, as turns
/// end; a cancelled or failed turn pauses them until the user sends again. The user can reorder
/// them, edit them, or send one ahead of the rest.
public struct PromptQueue: Equatable, Sendable {
    public struct Item: Identifiable, Hashable, Sendable {
        public let id: UUID
        public var text: String
        /// Whether the message shows in the transcript when it goes out. Messages other sessions
        /// send through Native's tools don't; the transcript records them as session messages.
        public let isEchoed: Bool
        /// Files and images that go with the text.
        public let attachments: [PromptAttachment]

        public init(id: UUID = UUID(), _ text: String, attachments: [PromptAttachment] = [], isEchoed: Bool = true) {
            self.id = id
            self.text = text
            self.attachments = attachments
            self.isEchoed = isEchoed
        }
    }

    /// Which way `move(_:_:)` takes a message.
    public enum Direction: Sendable {
        /// Sooner: toward the front of the queue.
        case up
        /// Later: toward the back.
        case down
    }

    public private(set) var items: [Item] = []
    public private(set) var isPaused = false

    public init() {}

    public var isEmpty: Bool {
        items.isEmpty
    }

    /// The messages the user sees: everything but the hidden ones (`isEchoed: false`), which keep
    /// their places among them.
    public var visible: [Item] {
        items.filter(\.isEchoed)
    }

    public mutating func append(_ text: String, attachments: [PromptAttachment] = [], isEchoed: Bool = true) {
        items.append(Item(text, attachments: attachments, isEchoed: isEchoed))
    }

    /// For a message that should go out before everything already waiting, such as one that
    /// arrived too late to steer the turn it was meant for.
    public mutating func prepend(_ text: String, attachments: [PromptAttachment] = [], isEchoed: Bool = true) {
        items.insert(Item(text, attachments: attachments, isEchoed: isEchoed), at: 0)
    }

    /// Edits a message; emptying one that carries no files removes it.
    public mutating func update(_ id: Item.ID, text: String) {
        guard let index = index(of: id) else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, items[index].attachments.isEmpty {
            items.remove(at: index)
        } else {
            items[index].text = text
        }
    }

    /// Puts a removed message back where it was, for undo.
    public mutating func restore(_ item: Item, at index: Int) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.insert(item, at: min(index, items.count))
    }

    public func index(of id: Item.ID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    @discardableResult
    public mutating func remove(_ id: Item.ID) -> Item? {
        guard let index = index(of: id) else { return nil }
        return items.remove(at: index)
    }

    /// Whether `move(_:_:)` would change anything: the message isn't already first or last among
    /// the visible ones.
    public func canMove(_ id: Item.ID, _ direction: Direction) -> Bool {
        let visible = visible
        guard let position = visible.firstIndex(where: { $0.id == id }) else { return false }
        return direction == .up ? position > 0 : position < visible.count - 1
    }

    /// Swaps a message with the visible one before or after it.
    public mutating func move(_ id: Item.ID, _ direction: Direction) {
        guard canMove(id, direction), let position = visible.firstIndex(where: { $0.id == id }) else { return }
        let neighbor = visible[direction == .up ? position - 1 : position + 1].id
        move(id, before: direction == .up ? neighbor : visible.dropFirst(position + 2).first?.id)
    }

    /// Moves a message to just before `target`, or to the back with no target: where a drag drops it.
    public mutating func move(_ id: Item.ID, before target: Item.ID?) {
        guard id != target, let item = remove(id) else { return }
        let destination = target.flatMap(index(of:)) ?? items.endIndex
        items.insert(item, at: destination)
    }

    /// The next message to send when a turn ends normally, unless the queue is paused.
    public mutating func next() -> Item? {
        guard !isPaused, !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    public mutating func pause() {
        isPaused = true
    }

    public mutating func resume() {
        isPaused = false
    }
}
