import Testing

@testable import AppAppearance

struct SettingsDetailScrollStateTests {
    @Test func backKeepsTheCataloguePositionUntilListLayout() {
        var state = SettingsDetailScrollState()
        state.openDetail(at: 1240.5)
        // A layout callback while details are showing must not consume the list position.
        #expect(state.listDidLayout() == nil)
        state.returnToList()
        #expect(state.listDidLayout() == 1240.5)
        #expect(state.listDidLayout() == nil)
    }

    @Test func replacingADetailKeepsTheOriginalPosition() {
        var state = SettingsDetailScrollState()
        state.openDetail(at: 1240.5)
        state.openDetail(at: 0)
        state.returnToList()
        #expect(state.listDidLayout() == 1240.5)
    }

    @Test func searchAndPageChangesDiscardPendingRestoration() {
        for returning in [false, true] {
            var state = SettingsDetailScrollState()
            state.openDetail(at: 1240.5)
            if returning { state.returnToList() }
            state.discard()
            state.returnToList()
            #expect(state.listDidLayout() == nil)
        }
    }

    @Test func eachVisitCapturesItsOwnPositionIncludingTheTop() {
        var state = SettingsDetailScrollState()
        for offset in [1240.5, 2380, 0] {
            state.openDetail(at: offset)
            state.returnToList()
            #expect(state.listDidLayout() == offset)
        }
    }

    @Test func returningWithoutADetailDoesNotMoveTheList() {
        var state = SettingsDetailScrollState()
        state.returnToList()
        #expect(state.listDidLayout() == nil)
    }
}
