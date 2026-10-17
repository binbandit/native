import Foundation
import Testing

@testable import Experiments

// A small catalog with one experiment of each tier, plus a second variant on the same point to
// make conflicts.

private protocol Greeter: Sendable {
    func greet(_ name: String) -> String
}

private struct PlainGreeter: Greeter {
    func greet(_ name: String) -> String { "Hello, \(name)." }
}

private struct LoudGreeter: Greeter {
    func greet(_ name: String) -> String { "HELLO, \(name.uppercased())!" }
}

private struct PoliteGreeter: Greeter {
    func greet(_ name: String) -> String { "Good day, \(name)." }
}

private enum Density: String, ParameterChoice {
    case compact, regular, roomy

    var title: String { rawValue.capitalized }
}

private let review = ReviewDate(year: 2027, month: 1, day: 31)

extension ExtensionPoint where Contract == any Greeter {
    fileprivate static var greeter: Self { Self(id: "greeter", title: "Greeting", default: PlainGreeter()) }
}

extension Gate {
    fileprivate static let hideRetry = Gate(
        id: "hide-retry", title: "Hide Retry", summary: "Hides the Retry button.", site: "Errors ▸ Retry",
        stage: .labs, owner: "tests", reviewBy: review
    )
    fileprivate static let fancyIcons = Gate(
        id: "fancy-icons", title: "Fancy icons", summary: "Uses fancy icons.", site: "Sidebar ▸ icons",
        stage: .beta, owner: "tests", reviewBy: review, requiresRelaunch: true
    )
}

extension Parameter where Value == Density {
    fileprivate static var density: Self {
        Self(
            id: "density", title: "Density", summary: "Row spacing.", site: "Transcript ▸ rows", stage: .beta,
            owner: "tests", reviewBy: review, default: .regular, domain: .allCases
        )
    }
}

extension Parameter where Value == Int {
    fileprivate static var foldThreshold: Self {
        Self(
            id: "fold-threshold", title: "Fold after", summary: "Calls before folding.", site: "Transcript ▸ tools",
            stage: .labs, owner: "tests", reviewBy: review, default: 2, domain: .range(2...6)
        )
    }
}

extension Variant {
    fileprivate static let loud = Variant(
        id: "loud", title: "Loud", summary: "Shouts.", stage: .labs, owner: "tests", reviewBy: review,
        claims: [Claim(.greeter, LoudGreeter())]
    )
    fileprivate static let polite = Variant(
        id: "polite", title: "Polite", summary: "Bows.", stage: .labs, owner: "tests", reviewBy: review,
        claims: [Claim(.greeter, PoliteGreeter())]
    )
}

private let catalog = ExperimentCatalog([
    Gate.hideRetry, Gate.fancyIcons, Parameter<Density>.density, Parameter<Int>.foldThreshold, Variant.loud,
    Variant.polite,
])

@MainActor
@Suite("Experiment store")
struct ExperimentStoreTests {
    @Test func everythingStartsAtItsDefault() {
        let store = ExperimentStore(catalog: catalog, storage: InMemoryExperimentStorage())

        #expect(store.value(of: .hideRetry) == false)
        #expect(store.value(of: .density) == .regular)
        #expect(store.value(of: .foldThreshold) == 2)
        #expect(store.implementation(of: .greeter).greet("Ada") == "Hello, Ada.")
        #expect(store.changed.isEmpty)
    }

    @Test func gatesAndParametersApplyLive() {
        let store = ExperimentStore(catalog: catalog, storage: InMemoryExperimentStorage())

        store.set(true, for: .hideRetry)
        store.set(.roomy, for: .density)
        store.set(4, for: .foldThreshold)

        #expect(store.value(of: .hideRetry))
        #expect(store.value(of: .density) == .roomy)
        #expect(store.value(of: .foldThreshold) == 4)
        #expect(store.changed == ["hide-retry", "density", "fold-threshold"])
    }

    @Test func settingTheDefaultForgetsTheSavedValue() {
        let storage = InMemoryExperimentStorage()
        let store = ExperimentStore(catalog: catalog, storage: storage)

        store.set(.compact, for: .density)
        store.set(.regular, for: .density)

        #expect(store.changed.isEmpty)
        #expect(storage.value(for: "density", as: .string) == nil)
    }

    @Test func valuesOutsideTheDomainReadAsTheDefault() {
        let storage = InMemoryExperimentStorage(["density": .string("gigantic"), "fold-threshold": .int(40)])
        let store = ExperimentStore(catalog: catalog, storage: storage)

        #expect(store.value(of: .density) == .regular)
        #expect(store.value(of: .foldThreshold) == 2)
        #expect(store.changed.isEmpty)

        store.set(9, for: .foldThreshold)
        #expect(store.value(of: .foldThreshold) == 2)
    }

    @Test func aVariantReplacesItsExtensionPointWhileItIsOn() {
        let store = ExperimentStore(catalog: catalog, storage: InMemoryExperimentStorage())

        store.setEnabled(true, for: .loud)
        #expect(store.implementation(of: .greeter).greet("Ada") == "HELLO, ADA!")
        #expect(store.current.extensions.outcome(for: "greeter") == .contributed(by: .experiment("loud")))

        store.setEnabled(false, for: .loud)
        #expect(store.implementation(of: .greeter).greet("Ada") == "Hello, Ada.")
        #expect(store.current.extensions.outcome(for: "greeter") == .standard)
    }

    @Test func conflictingVariantsFallBackToTheDefaultAndSaySo() {
        let store = ExperimentStore(catalog: catalog, storage: InMemoryExperimentStorage())

        store.setEnabled(true, for: .polite)
        store.setEnabled(true, for: .loud)

        #expect(store.implementation(of: .greeter).greet("Ada") == "Hello, Ada.")
        let conflict = ExtensionConflict(
            point: "greeter", pointTitle: "Greeting", sources: [.experiment("loud"), .experiment("polite")]
        )
        #expect(store.conflicts == [conflict])

        store.setEnabled(false, for: .loud)
        #expect(store.conflicts.isEmpty)
        #expect(store.implementation(of: .greeter).greet("Ada") == "Good day, Ada.")
    }

    @Test func relaunchExperimentsKeepTheirLaunchValueUntilTheNextLaunch() {
        let storage = InMemoryExperimentStorage()
        let store = ExperimentStore(catalog: catalog, storage: storage)

        store.set(true, for: .fancyIcons)
        #expect(store.value(of: .fancyIcons) == false)
        #expect(store.saved.value(of: .fancyIcons))
        #expect(store.needsRelaunch("fancy-icons"))

        let relaunched = ExperimentStore(catalog: catalog, storage: storage)
        #expect(relaunched.value(of: .fancyIcons))
        #expect(!relaunched.needsRelaunch("fancy-icons"))

        relaunched.set(false, for: .fancyIcons)
        #expect(relaunched.value(of: .fancyIcons))
        #expect(relaunched.needsRelaunch("fancy-icons"))
    }

    @Test func resetAllCanBeUndone() {
        let store = ExperimentStore(catalog: catalog, storage: InMemoryExperimentStorage())
        store.set(true, for: .hideRetry)
        store.setEnabled(true, for: .loud)
        let before = store.saved.overrides

        store.resetAll()
        #expect(store.changed.isEmpty)
        #expect(store.implementation(of: .greeter).greet("Ada") == "Hello, Ada.")

        store.setOverrides(before)
        #expect(store.value(of: .hideRetry))
        #expect(store.isEnabled(.loud))
    }

    @Test func snapshotsResolveContractsOffTheMainActor() async {
        let store = ExperimentStore(catalog: catalog, storage: InMemoryExperimentStorage())
        store.setEnabled(true, for: .polite)
        let snapshot = store.current

        let greeting = await Task.detached { snapshot.implementation(of: .greeter).greet("Ada") }.value
        #expect(greeting == "Good day, Ada.")
    }
}

@Suite("User defaults storage")
struct UserDefaultsStorageTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "experiments-tests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test func valuesRoundTripByKind() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = UserDefaultsExperimentStorage(defaults)

        storage.setValue(.bool(true), for: "a")
        storage.setValue(.int(3), for: "b")
        storage.setValue(.double(1.5), for: "c")
        storage.setValue(.string("roomy"), for: "d")

        #expect(storage.value(for: "a", as: .bool) == .bool(true))
        #expect(storage.value(for: "b", as: .int) == .int(3))
        #expect(storage.value(for: "c", as: .double) == .double(1.5))
        #expect(storage.value(for: "d", as: .string) == .string("roomy"))
        #expect(defaults.bool(forKey: "experiment.a"))

        storage.setValue(nil, for: "a")
        #expect(defaults.object(forKey: "experiment.a") == nil)
    }

    @MainActor
    @Test func aValueOfTheWrongKindReadsAsNothing() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("yes", forKey: "experiment.hide-retry")

        let store = ExperimentStore(catalog: catalog, storage: UserDefaultsExperimentStorage(defaults))
        #expect(store.value(of: .hideRetry) == false)
    }
}

@Suite("Review dates")
struct ReviewDateTests {
    @Test func dueFromTheStartOfTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = ReviewDate(year: 2027, month: 1, day: 31)
        let start = try #require(date.date(in: calendar))

        #expect(!date.isDue(at: start.addingTimeInterval(-1), calendar: calendar))
        #expect(date.isDue(at: start, calendar: calendar))
    }
}
