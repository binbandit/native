import Foundation
import Testing

@testable import Experiments

private protocol Greeter: Sendable {
    func greet() -> String
}

private struct PlainGreeter: Greeter {
    func greet() -> String { "Hello." }
}

private struct PluginGreeter: Greeter {
    func greet() -> String { "Hello from Acme." }
}

extension ExtensionPoint where Contract == any Greeter {
    fileprivate static var greeter: Self { Self(id: "greeter", title: "Greeting", default: PlainGreeter()) }
}

private let review = ReviewDate(year: 2027, month: 1, day: 31)

private func decode(_ json: String) throws -> ManifestExperimentList {
    try JSONDecoder().decode(ManifestExperimentList.self, from: Data(json.utf8))
}

@Suite("Plugin experiments")
struct PluginExperimentsTests {
    private let manifest = """
        [
          { "id": "fast-review", "kind": "gate", "title": "Fast review", "summary": "Adds a quick review.",
            "reviewBy": "2027-01-31" },
          { "id": "verbosity", "kind": "parameter", "title": "Verbosity", "summary": "How much the server says.",
            "stage": "beta", "reviewBy": "2027-01-31", "default": "low",
            "options": [{ "value": "low", "title": "Low" }, { "value": "high" }] },
          { "id": "results", "kind": "parameter", "title": "Results", "summary": "How many.",
            "reviewBy": "2027-01-31", "default": 9, "range": { "min": 1, "max": 5 } },
          { "id": "broken", "kind": "gate", "summary": "No title." }
        ]
        """

    @Test func eachExperimentIsCheckedOnItsOwn() throws {
        let uses: [PluginExperiments.Use] = [
            .init(experiment: "fast-review", role: .switches, place: "workflow “Fast review”"),
            .init(experiment: "verbosity", role: .fills, place: "MCP server “search”"),
            .init(experiment: "verbosity", role: .switches, place: "agent “Acme”"),
            .init(experiment: "missing", role: .fills, place: "agent “Acme”"),
        ]
        let result = PluginExperiments(
            plugin: "acme", name: "Acme", declared: try decode(manifest), uses: uses, reserved: []
        )

        #expect(result.descriptors.map(\.id) == ["acme.fast-review", "acme.verbosity"])
        #expect(result.descriptors.allSatisfy { $0.origin == .plugin(id: "acme", name: "Acme") })
        #expect(result.descriptors[0].touches.map(\.title) == ["workflow “Fast review”"])
        #expect(result.descriptors[1].stage == .beta)
        #expect(Set(result.problems.compactMap(\.experiment)) == ["broken", "results", "missing", "verbosity"])
    }

    @Test func idsTakenElsewhereAreProblems() throws {
        let result = PluginExperiments(
            plugin: "acme", name: "Acme", declared: try decode(manifest), uses: [], reserved: ["acme.fast-review"]
        )
        #expect(!result.descriptors.map(\.id).contains("acme.fast-review"))
        #expect(result.problems.contains { $0.experiment == "fast-review" })
    }

    @Test func aListThatIsNotAListIsOneProblem() throws {
        let list = try decode(#"{ "id": "x" }"#)
        #expect(list.valid.isEmpty)
        #expect(list.malformed.count == 1)
    }

    @Test func placeholdersAreFoundAndFilled() {
        let text = "--level=${experiment:verbosity} --max ${experiment:results}"
        #expect(ExperimentPlaceholder.references(in: text) == ["verbosity", "results"])
        let filled = ExperimentPlaceholder.substitute(in: text) { $0 == "verbosity" ? "high" : "3" }
        #expect(filled == "--level=high --max 3")
    }
}

@MainActor
@Suite("Contributed experiments")
struct ContributedExperimentsTests {
    private static let variant = Variant(
        id: ExperimentID(namespace: "acme", "greeter"), title: "Acme greeting", summary: "Greets as Acme.",
        stage: .labs, owner: "Acme", reviewBy: review, claims: [Claim(.greeter, PluginGreeter())]
    )

    @Test func pluginExperimentsComeAndGoWithTheirPlugin() {
        let storage = InMemoryExperimentStorage()
        let store = ExperimentStore(catalog: ExperimentCatalog([]), storage: storage)
        let descriptor = Self.variant.descriptor.contributed(byPlugin: "acme", named: "Acme")

        store.setContributedExperiments([descriptor])
        store.setEnabled(true, for: Self.variant)
        #expect(store.implementation(of: .greeter).greet() == "Hello from Acme.")
        #expect(store.catalog.groups.map(\.id) == ["plugin.acme"])

        // Turning the plugin off removes the experiment and its claim, but keeps the user's choice.
        store.setContributedExperiments([])
        #expect(store.implementation(of: .greeter).greet() == "Hello.")
        #expect(store.catalog.experiments.isEmpty)

        store.setContributedExperiments([descriptor])
        #expect(store.implementation(of: .greeter).greet() == "Hello from Acme.")
    }

    @Test func namespacing() {
        let id = ExperimentID(namespace: "acme", "fast-mode")
        #expect(id.rawValue == "acme.fast-mode")
        #expect(id.isNamespaced(by: "acme"))
        #expect(!ExperimentID("acme").isNamespaced(by: "acme"))
        #expect(!id.isNamespaced(by: "ac"))
    }
}
