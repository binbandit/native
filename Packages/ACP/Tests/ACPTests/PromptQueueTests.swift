import Testing

@testable import ACP

struct PromptQueueTests {
    private func queue(_ texts: String...) -> PromptQueue {
        var queue = PromptQueue()
        for text in texts {
            queue.append(text)
        }
        return queue
    }

    private func texts(_ queue: PromptQueue) -> [String] {
        queue.items.map(\.text)
    }

    @Test func movingSwapsWithTheNeighbor() {
        var queue = queue("a", "b", "c")
        let c = queue.items[2].id
        queue.move(c, .up)
        #expect(texts(queue) == ["a", "c", "b"])
        queue.move(c, .up)
        #expect(texts(queue) == ["c", "a", "b"])
        queue.move(c, .down)
        #expect(texts(queue) == ["a", "c", "b"])
        queue.move(c, .down)
        #expect(texts(queue) == ["a", "b", "c"])
    }

    @Test func theEndsDontMoveFurther() {
        var queue = queue("a", "b")
        let a = queue.items[0].id
        let b = queue.items[1].id
        #expect(!queue.canMove(a, .up))
        #expect(!queue.canMove(b, .down))
        queue.move(a, .up)
        queue.move(b, .down)
        #expect(texts(queue) == ["a", "b"])
    }

    @Test func hiddenMessagesDontCountAsNeighbors() {
        var queue = PromptQueue()
        queue.append("a")
        queue.append("hidden", isEchoed: false)
        queue.append("b")
        let b = queue.items[2].id
        #expect(queue.canMove(b, .up))
        queue.move(b, .up)
        #expect(queue.visible.map(\.text) == ["b", "a"])
        #expect(!queue.canMove(b, .up))
    }

    @Test func droppingPutsAMessageBeforeTheTargetOrLast() {
        var queue = queue("a", "b", "c")
        let (a, c) = (queue.items[0].id, queue.items[2].id)
        queue.move(c, before: a)
        #expect(texts(queue) == ["c", "a", "b"])
        queue.move(c, before: nil)
        #expect(texts(queue) == ["a", "b", "c"])
        queue.move(a, before: a)
        #expect(texts(queue) == ["a", "b", "c"])
    }

    @Test func aPausedQueueHoldsItsMessages() {
        var queue = queue("a", "b")
        queue.pause()
        #expect(queue.next() == nil)
        queue.resume()
        #expect(queue.next()?.text == "a")
        #expect(texts(queue) == ["b"])
    }

    @Test func emptyingAnEditRemovesTheMessage() {
        var queue = queue("a", "b")
        queue.update(queue.items[0].id, text: "  ")
        #expect(texts(queue) == ["b"])
    }
    @Test func aSteerWhoseTurnEndedKeepsItsExplicitQueuePosition() throws {
        var queue = PromptQueue()
        let held = PromptQueue.Item("held steer", steersAfterTools: true, waitingForTool: "sleep 20")
        queue.restore(held, at: 0)
        queue.append("ordinary queue")
        let ordinary = try #require(queue.items.last)
        queue.pause()
        queue.endSteering()
        queue.move(ordinary.id, before: held.id)
        #expect(queue.isPaused)
        #expect(queue.visible.map(\.text) == ["ordinary queue", "held steer"])
        queue.resume()
        #expect(queue.next()?.id == ordinary.id)
        let popped = queue.next()
        let next = try #require(popped)
        #expect(next.id == held.id)
        #expect(!next.steersAfterTools)
        #expect(next.waitingForTool == nil)
    }

}
