import SessionTools
import Testing

struct SessionToolPanelLayoutTests {
    private func layout(_ open: [SessionToolPlace: SessionToolID], width: Double) -> SessionToolPanelLayout {
        SessionToolPanelLayout(open: open, availableWidth: width, minimumConversationWidth: 520, panelWidth: 420)
    }

    @Test func resizingMovesTheSameOpenToolWithoutClosingIt() {
        let open: [SessionToolPlace: SessionToolID] = [.side: "changes"]
        let narrow = layout(open, width: 939)
        #expect(narrow.docked == nil)
        #expect(narrow.overlay == "changes")
        let wide = layout(open, width: 940)
        #expect(wide.docked == "changes")
        #expect(wide.overlay == nil)
        #expect(layout(open, width: 939) == narrow)
    }

    @Test func closedPanelsStayAbsentAtEveryWidth() {
        for width in [0.0, 600, 940, 1600] {
            let result = layout([:], width: width)
            #expect(result.docked == nil)
            #expect(result.overlay == nil)
        }
    }

    @Test func factPlacementAlwaysOverlays() {
        for width in [600.0, 1600] {
            let result = layout([.fact: "changes"], width: width)
            #expect(result.docked == nil)
            #expect(result.overlay == "changes")
        }
    }
}
