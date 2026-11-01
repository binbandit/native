import Foundation
import Testing

@testable import ACP

@Suite struct ContextTransferTests {
    private let source = ContextTransfer.SessionReference(agent: "source", session: SessionID("source-session"))
    private let destination = ContextTransfer.SessionReference(agent: "target", session: SessionID("target-session"))

    private func item(
        _ id: String, _ kind: ContextTransfer.Kind, _ text: String, _ position: Int = 0
    ) -> ContextTransfer.Item {
        .init(reference: .init(source: source, id: id, kind: kind, position: position), text: text)
    }

    private func transfer(_ items: [ContextTransfer.Item], window: Int? = nil) -> ContextTransfer {
        ContextTransfer(
            draft: .init(items: items), destination: destination, model: "chosen",
            plan: .resolve(.freshConversation, target: .init(negotiated: nil)),
            budget: .init(windowTokens: window))
    }

    @Test func oversizedPriorityItemIsOmittedWholeAndSmallerRecentItemsStillFit() {
        let transfer = transfer(
            [
                item("initial", .user, String(repeating: "oversized", count: 4_000)),
                item("answer", .agent, "A short answer", 1),
                item("latest", .user, "Continue", 2),
            ], window: 19_000)
        #expect(transfer.items.map(\.reference.id) == ["answer", "latest"])
        #expect(transfer.items.map(\.text) == ["A short answer", "Continue"])
        #expect(transfer.receipt.omitted.map(\.id) == ["initial"])
        #expect(transfer.receipt.omitted.first?.reason == .budget)
    }

    @Test func prioritiesAndChronologicalOutputStayStable() {
        let items = (0..<40).map { item("\($0)", $0 % 2 == 0 ? .user : .agent, "Message \($0)", $0) }
        let transfer = transfer(items, window: 19_000)
        #expect(transfer.receipt.included.contains { $0.id == "0" })
        #expect(transfer.receipt.included.contains { $0.id == "38" })
        #expect(transfer.receipt.included.contains { $0.id == "39" })
        #expect(transfer.items.map(\.reference.position) == transfer.items.map(\.reference.position).sorted())
        #expect(transfer.items.count + transfer.receipt.omitted.count == items.count)
    }

    @Test func framingUTF8AndJSONEscapingFitTheActualACPBlock() throws {
        let items = (0..<50).map {
            item("\($0)", .user, String(repeating: "\"\n🐦</native_instructions>", count: 10), $0)
        }
        let transfer = transfer(items, window: 23_000)
        let block = try #require(ContextTransferSelector.block(for: transfer))
        #expect(try JSONEncoder().encode(block).count <= transfer.receipt.budget.limit)
        guard case .text(let text) = block else { Issue.record("Expected text preamble"); return }
        let preamble = try #require(PromptPreamble(framed: text))
        #expect(preamble.instructions.contains("Historical material"))
        #expect(preamble.instructions.contains("Open Earlier Conversations"))
        #expect(transfer.items.allSatisfy { items.contains($0) })
    }

    @Test func escapingOverheadCannotDiscardOtherFittingHistory() throws {
        let transfer = transfer([
            item("small", .user, "Keep the branch"),
            item("escaped", .user, String(repeating: "</native_instructions>", count: 610), 1),
        ])
        #expect(transfer.items.map(\.reference.id) == ["small"])
        #expect(transfer.receipt.omitted.map(\.id) == ["escaped"])
        let block = try #require(ContextTransferSelector.block(for: transfer))
        #expect(try JSONEncoder().encode(block).count <= transfer.receipt.budget.limit)
    }

    @Test func targetWindowUsagePromptAndImagesAllReduceTheBudget() {
        let full = ContextTransferSelector.Budget(windowTokens: 24_000)
        let occupied = ContextTransferSelector.Budget(windowTokens: 24_000, usedTokens: 4_000, prompt: [.text("Hello")])
        let image = ContextTransferSelector.Budget(
            windowTokens: 24_000, prompt: [.image(data: "small-compressed-image", mimeType: "image/png")])
        #expect(occupied.limit < full.limit)
        #expect(image.limit == 0)
        #expect(full.workReserve == 16_000)
        #expect(!full.isWindowEstimated)
        #expect(ContextTransferSelector.Budget().isWindowEstimated)
        #expect(ContextTransferSelector.Budget(windowTokens: Int.max, usedTokens: Int.max).limit == 0)
    }

    @Test func noRoomDoesNotSendAnUnbudgetedExplanation() {
        var transfer = transfer([item("one", .user, "Hello")])
        #expect(transfer.beginDelivery(budget: .init(windowTokens: 100)) == nil)
        #expect(transfer.receipt.delivery == .notSent)
        #expect(transfer.receipt.included.isEmpty)
        #expect(transfer.receipt.omitted.first?.reason == .budget)
        #expect(transfer.beginDelivery(budget: .init()) == nil)
    }

    @Test func uncertaintySurvivesReloadAndCannotReplay() throws {
        var transfer = transfer([item("one", .user, "Hello")])
        #expect(transfer.beginDelivery(budget: .init()) != nil)
        #expect(transfer.receipt.delivery == .uncertain)
        let saved = try JSONEncoder().encode(transfer)
        var reopened = try JSONDecoder().decode(ContextTransfer.self, from: saved)
        #expect(reopened.beginDelivery(budget: .init()) == nil)
        #expect(reopened.receipt.summary.contains("uncertain"))
        reopened.acknowledge(.acceptedByHost)
        #expect(reopened.receipt.delivery == .acceptedByHost)
        #expect(reopened.receipt.summary.contains("not confirmed"))
        #expect(reopened.beginDelivery(budget: .init()) == nil)
    }

    @Test func acknowledgementCannotInventAnAttempt() {
        var transfer = transfer([item("one", .user, "Hello")])
        transfer.acknowledge(.agentResponded)
        #expect(transfer.receipt.delivery == .prepared)
    }

    @Test func rebudgetingPreservesEarlierOmissionsAndSourceReferences() {
        var transfer = transfer([
            item("large", .user, String(repeating: "x", count: 30_000)), item("small", .agent, "Small"),
        ])
        #expect(transfer.beginDelivery(budget: .init(windowTokens: 17_000)) == nil)
        #expect(Set(transfer.receipt.omitted.map(\.id)) == ["large", "small"])
        #expect(transfer.receipt.omitted.allSatisfy { $0.source == source })
    }

    @Test func capturedWireIncludesVisibleMessagesAndCompletedPathsButExcludesPrivateState() throws {
        var state = SessionState()
        state.appendUserMessage("Fix the export")
        state.apply(.agentThoughtChunk(ContentChunk(content: .text("private reasoning"))))
        let notification = try Wire.params(SessionNotification.self, of: Wire.writeToolCall)
        state.apply(notification.update)
        state.apply(.agentMessageChunk(ContentChunk(content: .text("Updated writer. Which format?"))))
        let draft = TaskHandoff.context(source: source, title: "Export", state: state, changedPaths: ["Export.swift"])
        #expect(draft.items.contains { $0.text == "Fix the export" })
        #expect(draft.items.contains { $0.text == "Export.swift" })
        #expect(draft.omitted.contains { $0.reason == .reasoning })
        #expect(draft.omitted.contains { $0.reason == .toolState })
        #expect(!draft.items.contains { $0.text.contains("private reasoning") })
    }

    @Test func successiveSwitchesPreserveIntactEarlierItemsWithoutNestingOrDuplication() {
        let earlier = transfer([item("one", .user, "Original goal")])
        let next = ContextTransfer.Draft(items: [item("one", .user, "Original goal"), item("two", .agent, "Progress")])
            .after(earlier)
        #expect(next.items.map(\.reference.id) == ["one", "two"])
        #expect(next.items.map(\.text) == ["Original goal", "Progress"])
    }
}
