import SessionTools
import Testing

struct SessionToolPresentationTests {
    let changes = SessionToolSpec(id: "changes", places: [.side, .fact, .off], defaultPlace: .side)

    @Test func closingWhileMakingRoomCancelsThePendingOpen() {
        var state = SessionToolPresentation()
        #expect(state.request(changes, arrangement: .init(), hasPane: true) == .side)
        #expect(state.contains(changes.id, at: .side))
        #expect(state.openByPlace.isEmpty)
        state.close(changes.id)
        state.present(changes.id, at: .side)
        #expect(state.openByPlace.isEmpty)
        #expect(!state.contains(changes.id, at: .side))
    }

    @Test func toolsListsPendingAndShownOnesSoRemovedOnesCanClose() {
        let board = SessionToolSpec(id: "acme.board", places: [.fact, .off], defaultPlace: .fact)
        var state = SessionToolPresentation()
        state.request(changes, arrangement: .init(), hasPane: true)
        state.request(board, arrangement: .init(), hasPane: true)
        state.present(board.id, at: .fact)
        #expect(state.tools == [changes.id, board.id])
        state.close(changes.id)
        state.present(changes.id, at: .side)
        #expect(state.tools == [board.id])
    }

    @Test func lastRequestedToolWinsItsPlace() {
        let other = SessionToolSpec(id: "other", places: [.side], defaultPlace: .side)
        var state = SessionToolPresentation()
        state.request(changes, arrangement: .init(), hasPane: true)
        state.request(other, arrangement: .init(), hasPane: true)
        state.present(changes.id, at: .side)
        #expect(state.openByPlace.isEmpty)
        state.present(other.id, at: .side)
        #expect(state.openByPlace == [.side: other.id])
        state.close(.side)
        #expect(state.openByPlace.isEmpty)
    }

    @Test func disabledAndActionOnlyToolsNeverOpen() {
        var state = SessionToolPresentation()
        var arrangement = SessionToolArrangement()
        arrangement.move(changes, to: .off)
        #expect(state.request(changes, arrangement: arrangement, hasPane: true) == nil)
        #expect(state.request(changes, arrangement: .init(), hasPane: false) == nil)
        state.present(changes.id, at: .side)
        #expect(state.openByPlace.isEmpty)
    }

    @Test func factPlacementIsHonoredAndCanCloseByID() {
        var state = SessionToolPresentation()
        var arrangement = SessionToolArrangement()
        arrangement.move(changes, to: .fact)
        #expect(state.request(changes, arrangement: arrangement, hasPane: true) == .fact)
        state.present(changes.id, at: .fact)
        #expect(state.openByPlace == [.fact: changes.id])
        state.close(changes.id)
        #expect(state.openByPlace.isEmpty)
    }
}
