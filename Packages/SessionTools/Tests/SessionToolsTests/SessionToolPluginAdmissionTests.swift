import SessionTools
import Testing

struct SessionToolPluginAdmissionTests {
    @Test func aPluginsToolLivesUnderItsOwnID() {
        let board = SessionToolSpec(id: "acme.board", places: [.side, .fact, .off], defaultPlace: .side)
        #expect(board.isAllowed(fromPlugin: "acme"))
        #expect(!board.isAllowed(fromPlugin: "other"))
        #expect(!board.isAllowed(fromPlugin: "acm"))
    }

    @Test func aPluginCantTakeABuiltInToolsPlace() {
        let changes = SessionToolSpec(id: "changes", places: [.side, .off], defaultPlace: .side)
        #expect(!changes.isAllowed(fromPlugin: "changes"))
        #expect(!SessionToolSpec(id: "acme.", places: [.side], defaultPlace: .side).isAllowed(fromPlugin: "acme"))
        #expect(!SessionToolSpec(id: ".board", places: [.side], defaultPlace: .side).isAllowed(fromPlugin: ""))
    }

    @Test func theWorkbenchIsOnlyNativesOwn() {
        let logs = SessionToolSpec(id: "acme.logs", places: [.workbench, .off], defaultPlace: .workbench)
        #expect(!logs.isAllowed(fromPlugin: "acme"))
    }
}
