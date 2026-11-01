import ACP
import Foundation
import Observation

/// Locally prepared context survives a quit before the next explicit message. Taking it is
/// irreversible: an uncertain send must never submit the context automatically a second time.
@Observable
final class AgentModelContinuations {
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "agentModelContinuations"
    struct Receipt: Codable {
        var source: SessionKey
        let sourceName: String
        let sourceModel: String
        var sourceModelValue: String?
        let agent: AgentDefinition.ID
        let agentName: String
        let modelValue: String?
        let modelName: String
        var isDismissed = false
        var permissionNotice: String?
        var confirmedChoices: [String: String]?
    }

    private var pending: [String: String]
    private var receipts: [String: Data]
    private var earlierContext: [String: String]
    private var transfers: [String: Data]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        transfers = defaults.dictionary(forKey: Self.storageKey + ".transfers") as? [String: Data] ?? [:]
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

    func hasPending(_ session: SessionKey) -> Bool {
        transfer(for: session)?.receipt.delivery == .prepared || pending[key(session)] != nil
    }

    func context(for session: SessionKey) -> String? {
        if let transfer = transfer(for: session), case .text(let text) = ContextTransferSelector.block(for: transfer) {
            return PromptPreamble(framed: text)?.instructions
        }
        return pending[key(session)] ?? earlierContext[key(session)]
    }

    func transfer(for session: SessionKey) -> ContextTransfer? {
        transfers[key(session)].flatMap { try? JSONDecoder().decode(ContextTransfer.self, from: $0) }
    }

    func pendingTransferID(for session: SessionKey) -> UUID? {
        guard let transfer = transfer(for: session), transfer.receipt.delivery == .prepared else { return nil }
        return transfer.receipt.id
    }

    func prepare(_ transfer: ContextTransfer, for session: SessionKey) {
        pending.removeValue(forKey: key(session))
        defaults.set(pending, forKey: Self.storageKey)
        keepTransfer(transfer, for: session)
    }

    private func keepTransfer(_ transfer: ContextTransfer, for session: SessionKey) {
        transfers[key(session)] = try? JSONEncoder().encode(transfer)
        defaults.set(transfers, forKey: Self.storageKey + ".transfers")
    }

    func acknowledge(_ id: UUID?, for session: SessionKey, as delivery: ContextTransfer.Delivery) {
        guard let id, var transfer = transfer(for: session), transfer.receipt.id == id else { return }
        transfer.acknowledge(delivery)
        keepTransfer(transfer, for: session)
    }

    func prepare(_ context: String, for session: SessionKey) {
        transfers.removeValue(forKey: key(session))
        defaults.set(transfers, forKey: Self.storageKey + ".transfers")
        pending[key(session)] = context
        defaults.set(pending, forKey: Self.storageKey)
    }

    func replace(_ old: SessionKey, with replacement: SessionKey) {
        if let data = transfers.removeValue(forKey: key(old)),
            var transfer = try? JSONDecoder().decode(ContextTransfer.self, from: data)
        {
            transfer.receipt.destination = .init(agent: replacement.agent.rawValue, session: replacement.id)
            keepTransfer(transfer, for: replacement)
        }
        defaults.set(transfers, forKey: Self.storageKey + ".transfers")
        if let context = pending.removeValue(forKey: key(old)) { pending[key(replacement)] = context }
        if let context = earlierContext.removeValue(forKey: key(old)) { earlierContext[key(replacement)] = context }
        defaults.set(earlierContext, forKey: Self.storageKey + ".earlier")
        if let receipt = receipts.removeValue(forKey: key(old)) { receipts[key(replacement)] = receipt }
        for (id, data) in receipts {
            guard var receipt = try? JSONDecoder().decode(Receipt.self, from: data), receipt.source == old else {
                continue
            }
            receipt.source = replacement
            receipts[id] = try? JSONEncoder().encode(receipt)
        }
        defaults.set(pending, forKey: Self.storageKey)
        defaults.set(receipts, forKey: Self.storageKey + ".receipts")
    }

    func remove(_ session: SessionKey) {
        transfers.removeValue(forKey: key(session))
        defaults.set(transfers, forKey: Self.storageKey + ".transfers")
        pending.removeValue(forKey: key(session))
        receipts.removeValue(forKey: key(session))
        earlierContext.removeValue(forKey: key(session))
        defaults.set(earlierContext, forKey: Self.storageKey + ".earlier")
        defaults.set(pending, forKey: Self.storageKey)
        defaults.set(receipts, forKey: Self.storageKey + ".receipts")
    }

    func take(
        for session: SessionKey, budget: ContextTransferSelector.Budget = .init()
    ) -> ContentBlock? {
        if var transfer = transfer(for: session) {
            let block = transfer.beginDelivery(budget: budget)
            keepTransfer(transfer, for: session)
            return block
        }
        guard let context = pending.removeValue(forKey: key(session)) else { return nil }
        earlierContext[key(session)] = context
        defaults.set(pending, forKey: Self.storageKey)
        defaults.set(earlierContext, forKey: Self.storageKey + ".earlier")
        return PromptPreamble(
            marker: .init(id: "task-continuation", label: "Earlier context"), instructions: context
        ).block
    }
}
