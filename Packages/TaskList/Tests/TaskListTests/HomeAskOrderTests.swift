import Foundation
import Testing

@testable import TaskList

struct HomeAskOrderTests {
    struct Ask {
        let id: Int
        let kind: HomeAskOrder.Kind
        let date: Date?
    }

    private let asks = [
        Ask(id: 1, kind: .plan, date: Date(timeIntervalSince1970: 1)),
        Ask(id: 2, kind: .approval, date: Date(timeIntervalSince1970: 3)),
        Ask(id: 3, kind: .question, date: Date(timeIntervalSince1970: 2)),
        Ask(id: 4, kind: .approval, date: Date(timeIntervalSince1970: 2)),
    ]

    @Test func quickestDecisionThenLongestWait() {
        #expect(order(.quickest, asks) == [4, 2, 3, 1])
        #expect(order(.oldest, asks) == [1, 3, 4, 2])
    }

    @Test func arrivalsDoNotReplaceTheAskBeingRead() {
        #expect(order(.quickest, asks, retaining: 2) == [2, 4, 3, 1])
        #expect(order(.quickest, asks.filter { $0.id != 2 }, retaining: 2) == [4, 3, 1])
    }

    @Test func unknownDatesAndTiesKeepTheirInputOrder() {
        let entries = [Ask(id: 5, kind: .approval, date: nil), Ask(id: 6, kind: .approval, date: nil)]
        #expect(order(.quickest, entries + asks) == [4, 2, 5, 6, 3, 1])
        #expect(order(.quickest, []) == [])
    }

    @Test func parentAndSiblingArrivalsRetainTheExactPermission() {
        struct Permission: Equatable {
            let owner: String
            let call: String
            let request: Int
        }
        let reading = Permission(owner: "child-z", call: "call-1", request: 1)
        let sibling = Permission(owner: "child-a", call: "call-1", request: 1)
        let parent = Permission(owner: "parent", call: "call-1", request: 1)
        let replacement = Permission(owner: "child-z", call: "call-1", request: 2)
        func selected(_ pending: [Permission]) -> Permission? {
            HomeAskOrder.first(pending, retaining: reading, id: { $0 })
        }
        #expect(selected([reading]) == reading)
        #expect(selected([sibling, reading]) == reading)
        #expect(selected([parent, sibling, reading]) == reading)
        #expect(selected([parent, sibling]) == parent)
        #expect(selected([replacement]) == replacement)
        #expect(selected([]) == nil)
    }

    private func order(_ order: HomeAskOrder, _ asks: [Ask], retaining current: Int? = nil) -> [Int] {
        order.sorted(asks, retaining: current, id: \.id, kind: \.kind, date: \.date).map(\.id)
    }
}
