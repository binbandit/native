import Testing

@testable import ACP

struct PromptQueueEditTests {
    @Test func startingTheEditedMessageEndsTheEdit() throws {
        var queue = PromptQueue()
        queue.append("First follow-up")
        queue.append("Second follow-up")
        let first = try #require(queue.visible.first)
        var edit = PromptQueueEdit(id: first.id)

        #expect(queue.next()?.id == first.id)
        edit.reconcile(with: queue.visible)

        #expect(edit.id == nil)
        #expect(queue.visible.map(\.text) == ["Second follow-up"])
    }

    @Test func otherMessagesStartingAndReorderingKeepTheEdit() throws {
        var queue = PromptQueue()
        queue.append("First follow-up")
        queue.append("Edited follow-up")
        queue.append("Last follow-up")
        let item = try #require(queue.visible.dropFirst().first)
        var edit = PromptQueueEdit(id: item.id)

        _ = queue.next()
        edit.reconcile(with: queue.visible)
        #expect(edit.id == item.id)

        queue.move(item.id, .down)
        queue.pause()
        #expect(queue.next() == nil)
        edit.reconcile(with: queue.visible)
        #expect(edit.id == item.id)
    }

    @Test func hostSnapshotsKeepTheEditOnlyWhileItsMessageIsQueued() {
        let item = PromptQueue.Item("Queued follow-up")
        let other = PromptQueue.Item("Another follow-up")
        var edit = PromptQueueEdit(id: item.id)

        let updated = PromptQueue.Item(id: item.id, "Updated follow-up")
        edit.reconcile(with: [other, updated])
        #expect(edit.id == item.id)

        edit.reconcile(with: [other])
        #expect(edit.id == nil)

        edit.reconcile(with: [other, updated])
        #expect(edit.id == nil)
    }

    @Test func drainingTheLastMessageEndsTheEdit() throws {
        var queue = PromptQueue()
        queue.append("Only follow-up")
        var edit = PromptQueueEdit(id: try #require(queue.visible.first).id)
        _ = queue.next()
        edit.reconcile(with: queue.visible)
        #expect(edit.id == nil)
    }
}
