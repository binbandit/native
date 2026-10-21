import SessionTools
import Testing

struct SessionToolLayoutTests {
    static let tools = [
        SessionToolSpec(id: "changes", places: [.side, .workbench, .fact, .off], defaultPlace: .side),
        SessionToolSpec(id: "run", places: [.fact, .off], defaultPlace: .fact),
        SessionToolSpec(id: "terminal", places: [.workbench, .side, .off], defaultPlace: .workbench),
        SessionToolSpec(id: "openIn", places: [.fact, .off], defaultPlace: .fact),
    ]

    @Test func aQuietTaskShowsOnlyFactsThatAlwaysHaveSomethingToSay() {
        let layout = SessionToolLayout(
            tools: Self.tools, arrangement: SessionToolArrangement(), withFacts: ["openIn"], withContent: [], open: [])
        #expect(layout.facts == ["openIn"])
        #expect(layout.side.isEmpty)
        #expect(layout.workbench.isEmpty)
    }

    @Test func toolsShowWhileTheyHaveSomethingAndTabsWhileOpen() {
        let layout = SessionToolLayout(
            tools: Self.tools, arrangement: SessionToolArrangement(), withFacts: ["changes", "run", "openIn"],
            withContent: ["changes", "terminal"], open: [])
        #expect(layout.facts == ["changes", "run", "openIn"])
        #expect(layout.side == ["changes"])
        #expect(layout.workbench == ["terminal"])
    }

    @Test func anOpenToolKeepsItsTabWithNothingInIt() {
        let layout = SessionToolLayout(
            tools: Self.tools, arrangement: SessionToolArrangement(), withFacts: [], withContent: [], open: ["terminal"]
        )
        #expect(layout.workbench == ["terminal"])
    }

    @Test func aToolTurnedOffShowsNothing() {
        var arrangement = SessionToolArrangement()
        for tool in Self.tools {
            arrangement.move(tool, to: .off)
        }
        let layout = SessionToolLayout(
            tools: Self.tools, arrangement: arrangement, withFacts: ["changes", "run", "openIn"],
            withContent: ["changes", "terminal"], open: ["terminal"])
        #expect(
            layout
                == SessionToolLayout(
                    tools: [], arrangement: arrangement, withFacts: [], withContent: [], open: []))
    }
}
