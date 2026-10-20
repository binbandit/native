import Foundation
import SessionTools
import Testing

struct SessionToolArrangementTests {
    static let terminal = SessionToolSpec(id: "terminal", places: [.workbench, .side, .off], defaultPlace: .workbench)

    @Test func aToolStartsInItsDefaultPlace() {
        #expect(SessionToolArrangement().place(of: Self.terminal) == .workbench)
    }

    @Test func movingKeepsOnlyPlacesThatDifferFromTheDefault() {
        var arrangement = SessionToolArrangement()
        arrangement.move(Self.terminal, to: .side)
        #expect(arrangement.place(of: Self.terminal) == .side)
        arrangement.move(Self.terminal, to: .workbench)
        #expect(arrangement.isDefault)
    }

    @Test func aToolNeverGoesWhereItCantLive() {
        var arrangement = SessionToolArrangement()
        arrangement.move(Self.terminal, to: .fact)
        #expect(arrangement.place(of: Self.terminal) == .workbench)
        #expect(arrangement.isDefault)
    }

    @Test func aPlaceTheToolNoLongerAllowsFallsBackToItsDefault() {
        var arrangement = SessionToolArrangement()
        arrangement.move(Self.terminal, to: .side)
        let narrowed = SessionToolSpec(id: "terminal", places: [.workbench, .off], defaultPlace: .workbench)
        #expect(arrangement.place(of: narrowed) == .workbench)
    }

    @Test func savesAsPlacesByToolAndSkipsPlacesItDoesntKnow() throws {
        var arrangement = SessionToolArrangement()
        arrangement.move(Self.terminal, to: .off)
        let data = try JSONEncoder().encode(arrangement)
        #expect(String(decoding: data, as: UTF8.self) == #"{"terminal":"off"}"#)

        let later = Data(#"{"terminal":"floating","changes":"workbench"}"#.utf8)
        let decoded = try JSONDecoder().decode(SessionToolArrangement.self, from: later)
        let changes = SessionToolSpec(id: "changes", places: [.side, .workbench, .off], defaultPlace: .side)
        #expect(decoded.place(of: Self.terminal) == .workbench)
        #expect(decoded.place(of: changes) == .workbench)
    }
}
