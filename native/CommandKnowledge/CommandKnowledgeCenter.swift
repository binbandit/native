import ACP
import ApprovalAnalysis
import Experiments
import Foundation
import NativePolicy
import Observation

/// Client-local coverage only. No telemetry pipeline, host RPC, or export reads this store.
@Observable
final class CommandKnowledgeCenter {
    static let shared = CommandKnowledgeCenter(
        url: URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Native", directoryHint: .isDirectory)
            .appending(path: "CommandKnowledge/unknown-programs.json"))
    static let choiceKey = "approvals.countUnknownPrograms"

    private(set) var entries: [UnknownCommandCounts.Entry] = []
    private(set) var message: String?
    private(set) var hasLoaded = false
    private(set) var userEnabled: Bool
    @ObservationIgnored private let store: UnknownCommandCounts?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var work: Task<Void, Never>?

    /// A nil URL keeps previews inert.
    init(
        url: URL?, defaults: UserDefaults = .standard, entries: [UnknownCommandCounts.Entry] = [],
        message: String? = nil, hasLoaded: Bool? = nil
    ) {
        store = url.map(UnknownCommandCounts.init)
        self.defaults = defaults
        self.entries = entries
        self.message = message
        self.hasLoaded = hasLoaded ?? (url == nil)
        userEnabled = defaults.object(forKey: Self.choiceKey) == nil || defaults.bool(forKey: Self.choiceKey)
    }

    static var isAvailable: Bool { ExperimentStore.shared.value(of: .composerNext) }
    var isAllowed: Bool { PolicyCenter.shared.policy.unknownCommandCountsEnabled }
    var isEnabled: Bool { Self.isAvailable && isAllowed && userEnabled }

    func setEnabled(_ enabled: Bool) {
        guard isAllowed else { return }
        userEnabled = enabled
        if store != nil { defaults.set(enabled, forKey: Self.choiceKey) }
        generation += 1
    }

    func note(_ requests: [ToolCallState], session: UUID, knowledge: CommandKnowledge) {
        guard isEnabled, store != nil else { return }
        for call in requests {
            guard let command = call.shellCommand,
                let program = ApprovalCommand(command: command, workingDirectory: "/", knowledge: knowledge)
                    .unknownProgram
            else { continue }
            let identity = "\(session)/\(call.id)"
            guard seen.count < 4096, seen.insert(identity).inserted else { continue }
            let expectedGeneration = generation
            let previous = work
            work = Task {
                await previous?.value
                guard isEnabled, expectedGeneration == generation, let store else { return }
                do {
                    try await store.record(program: program, enabled: isEnabled)
                    message = nil
                    await refresh()
                } catch { message = error.localizedDescription }
            }
        }
    }

    func refresh() async {
        guard let store else { return }
        do {
            entries = try await store.top()
            hasLoaded = true
        } catch {
            hasLoaded = true
            message = error.localizedDescription
        }
    }

    func clear() async {
        generation += 1
        guard let store else { entries = []; return }
        // Finish earlier reads and writes before deleting, so their completions cannot restore a
        // stale list. New requests queue after the purge; old queued observations fail their epoch.
        let previous = work
        let clearing = Task {
            await previous?.value
            do {
                try await store.purge()
                entries = []
                hasLoaded = true
                message = "Local counts cleared. New unknown requests will be counted only while counting is on."
            } catch { message = error.localizedDescription }
        }
        work = clearing
        await clearing.value
    }
}
