import SessionTools
import Testing

struct SessionToolToolbarLayoutTests {
    private func layout(conversation: Double, title: Double) -> SessionToolToolbarLayout {
        SessionToolToolbarLayout(
            conversationWidth: conversation, titleOffset: 20, titleIdealWidth: title, wellWidth: 340,
            compactWellWidth: 180, gap: 12, minimumTitleWidth: 40)
    }

    @Test func aWideWindowGivesTheTitleAllTheRoomBeforeTheWell() {
        let wide = layout(conversation: 1180, title: 230)
        #expect(wide.wellWidth == 340)
        // Up to the well's leading edge, less the gap.
        #expect(wide.titleWidth == (1180 - 340) / 2 - 20 - 12)
    }

    @Test func theWellGivesWayBeforeTheTitleTruncates() {
        let docked = layout(conversation: 760, title: 230)
        #expect(docked.wellWidth == 760 - 2 * (20 + 230 + 12))
        #expect(docked.titleWidth == 230)
    }

    @Test func pastTheWellsCompactWidthTheTitleTruncatesKeepingTheGap() {
        let narrow = layout(conversation: 600, title: 400)
        #expect(narrow.wellWidth == 180)
        #expect(narrow.titleWidth == (600 - 180) / 2 - 20 - 12)
    }

    @Test func theTitleNeverVanishes() {
        #expect(layout(conversation: 200, title: 300).titleWidth == 40)
    }
}
