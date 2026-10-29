import ACP
import Experiments
import Foundation
import Modes
import Observation

/// Which mode each task is in, and putting a task in one. A mode's settings change at once,
/// through the session like any other change; its instructions go to the agent once, ahead of the
/// next prompt (`SessionHooks.preamble`). Each task's choice (`ModeSelection`) is kept in the user
/// defaults as `sessionModes`, by agent and session, so it's there after a restart.
@MainActor
@Observable
final class TaskModes {
    static let shared = TaskModes()

    let library: ModeLibrary
    private var selections: [String: ModeSelection] {
        didSet {
            if let data = try? JSONEncoder().encode(selections) {
                defaults.set(data, forKey: Self.selectionsKey)
            }
        }
    }
    /// The checkout of the project a session's task belongs to, whose modes it can use. Set at launch.
    @ObservationIgnored var projectRoot: (SessionModel) -> URL? = { _ in nil }
    @ObservationIgnored private let defaults: UserDefaults

    private static let selectionsKey = "sessionModes"

    init(library: ModeLibrary = .shared, defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults
        selections =
            defaults.data(forKey: Self.selectionsKey)
            .flatMap { try? JSONDecoder().decode([String: ModeSelection].self, from: $0) } ?? [:]
    }

    private static func key(_ session: SessionModel) -> String {
        "\(session.agent.id.rawValue)/\(session.id.rawValue)"
    }

    // MARK: - Reading

    func catalog(for session: SessionModel) -> ModeCatalog {
        library.catalog(forProjectAt: projectRoot(session))
    }

    /// The mode the task is in. One that's gone (a deleted mode, a project file removed) reads as
    /// Build, as does a task that was never put in one.
    func mode(of session: SessionModel) -> Mode {
        let selection = selections[Self.key(session)] ?? ModeSelection()
        return catalog(for: session).mode(selection.effectiveMode(options: session.configOptions)) ?? .build
    }

    /// What `mode` does on the session's agent, with the organization's policy applied.
    func resolution(of mode: Mode, on session: SessionModel) -> ModeResolution {
        ModeResolver.resolve(mode, options: session.state.configOptions) { option, value in
            !PolicyPermissionModes.forbids(option, value: value)
        }
    }

    /// The instructions to send ahead of the session's next prompt (`SessionHooks.preamble`).
    func preamble(for session: SessionModel, delivered: PromptPreamble.Marker?) -> PromptPreamble? {
        let mode = mode(of: session)
        return ModeInstructions.preamble(for: mode, resolution(of: mode, on: session), delivered: delivered)
    }

    // MARK: - Changing

    /// Puts the task in `id`: the settings the last mode changed go back, this one's are set, and
    /// what the organization overrode is said once in the transcript. The instructions wait for the
    /// next prompt, so a turn that's running carries on as it began.
    func select(_ id: Mode.ID, in session: SessionModel) async {
        guard let mode = catalog(for: session).mode(id) else { return }
        await apply(mode, to: session)
    }

    private func apply(_ mode: Mode, to session: SessionModel) async {
        let options = session.state.configOptions
        let resolution = resolution(of: mode, on: session)
        let current = selections[Self.key(session)] ?? ModeSelection()
        let (changes, next) = current.switching(to: mode.id, resolution, options: options)
        selections[Self.key(session)] = next
        for change in changes {
            // Read again each time: the model's change can change what the rest offer.
            guard let option = session.state.configOptions.first(where: { $0.id == change.optionID }) else { continue }
            await session.setConfigOption(option, to: change.value)
        }
        let policy = resolution.limits.filter(\.isPolicy)
        if !policy.isEmpty {
            session.addNotice(
                policy.map {
                    $0.text(agent: session.agentName, mode: mode.label, organization: PolicyCenter.organizationSubject)
                }.joined(separator: " "),
                isError: false)
        }
    }

    /// The next mode in the picker's order (⌃⇧M).
    func selectNext(in session: SessionModel) async {
        await select(catalog(for: session).next(after: mode(of: session).id).id, in: session)
    }

    func recoverSelection(from old: SessionKey, to session: SessionModel) {
        selections[Self.key(session)] = selections["\(old.agent.rawValue)/\(old.id.rawValue)"]
    }

    /// A task the user just started in the project at `projectRoot`: in the mode it carries on from
    /// (`/clear`), else in the mode new tasks there start in. The root comes from the launch, since
    /// `projectRoot(session)` only finds the task once the catalog lists it.
    func taskStarted(_ session: SessionModel, continuing earlier: SessionModel?, projectRoot root: URL?) async {
        if let earlier {
            // Its settings come across with the rest of the task's (`adoptSettings`).
            selections[Self.key(session)] = selections[Self.key(earlier)]
            return
        }
        let root = root ?? projectRoot(session)
        if let root, !library.hasRead(projectAt: root) {
            library.refresh(projectAt: root)
        }
        let plainly = ExperimentStore.shared.value(of: .settingsPlainly)
        if plainly, let root { await library.finishReading(projectAt: root) }
        let starting = plainly ? library.startingMode(forProjectAt: root) : library.startingMode
        guard starting.id != .build else { return }
        await apply(starting, to: session)
    }
}
