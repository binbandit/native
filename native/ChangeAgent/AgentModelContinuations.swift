import ACP
import Foundation

/// Locally prepared context survives a quit before the next explicit message. Taking it is
/// irreversible: an uncertain send must never submit the context automatically a second time.
final class AgentModelContinuations {
    private let defaults: UserDefaults
    private static let storageKey = "agentModelContinuations"
    struct Receipt: Codable {
        let source: SessionKey
        let sourceName: String
        let sourceModel: String
        var sourceModelValue: String?
        let agent: AgentDefinition.ID
        let agentName: String
        let modelValue: String?
        let modelName: String
        var isDismissed = false
        var confirmedChoices: [String: String]?
    }

    private var pending: [String: String]
    private var receipts: [String: Data]
    private var earlierContext: [String: String]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        earlierContext = defaults.dictionary(forKey: Self.storageKey + ".earlier") as? [String: String] ?? [:]
        pending = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        receipts = defaults.dictionary(forKey: Self.storageKey + ".receipts") as? [String: Data] ?? [:]
    }

    private func key(_ session: SessionKey) -> String {
        "\(session.agent.rawValue.count):\(session.agent.rawValue)\(session.id.rawValue)"
    }

    func receipt(for session: SessionKey) -> Receipt? {
        receipts[key(session)].flatMap { try? JSONDecoder().decode(Receipt.self, from: $0) }
    }

    func keep(_ receipt: Receipt, for session: SessionKey) {
        receipts[key(session)] = try? JSONEncoder().encode(receipt)
        defaults.set(receipts, forKey: Self.storageKey + ".receipts")
    }

    func hasPending(_ session: SessionKey) -> Bool { pending[key(session)] != nil }
    func context(for session: SessionKey) -> String? { pending[key(session)] ?? earlierContext[key(session)] }

    func prepare(_ context: String, for session: SessionKey) {
        pending[key(session)] = context
        defaults.set(pending, forKey: Self.storageKey)
    }

    func replace(_ old: SessionKey, with replacement: SessionKey) {
        if let context = pending.removeValue(forKey: key(old)) { pending[key(replacement)] = context }
        if let context = earlierContext.removeValue(forKey: key(old)) { earlierContext[key(replacement)] = context }
        defaults.set(earlierContext, forKey: Self.storageKey + ".earlier")
        if let receipt = receipts.removeValue(forKey: key(old)) { receipts[key(replacement)] = receipt }
        defaults.set(pending, forKey: Self.storageKey)
        defaults.set(receipts, forKey: Self.storageKey + ".receipts")
    }

    func remove(_ session: SessionKey) {
        pending.removeValue(forKey: key(session))
        receipts.removeValue(forKey: key(session))
        earlierContext.removeValue(forKey: key(session))
        defaults.set(earlierContext, forKey: Self.storageKey + ".earlier")
        defaults.set(pending, forKey: Self.storageKey)
        defaults.set(receipts, forKey: Self.storageKey + ".receipts")
    }

    func take(for session: SessionKey) -> ContentBlock? {
        guard let context = pending.removeValue(forKey: key(session)) else { return nil }
        earlierContext[key(session)] = context
        defaults.set(pending, forKey: Self.storageKey)
        defaults.set(earlierContext, forKey: Self.storageKey + ".earlier")
        return PromptPreamble(
            marker: .init(id: "task-continuation", label: "Earlier context"), instructions: context
        ).block
    }
}
