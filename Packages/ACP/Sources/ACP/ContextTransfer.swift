import Foundation

/// Locally selected historical context, separate from the host's task and turn history.
public struct ContextTransfer: Codable, Equatable, Sendable {
    public struct SessionReference: Codable, Equatable, Hashable, Sendable {
        public var agent: String
        public var session: SessionID

        public init(agent: String, session: SessionID) {
            self.agent = agent
            self.session = session
        }
    }

    public enum Kind: String, Codable, Sendable { case user, agent, goal, plan, file, status, legacy }

    public struct Reference: Codable, Equatable, Hashable, Sendable {
        public let source: SessionReference
        /// Transcript-local identity, not an agent's native message id or a canonical turn id.
        public let id: String
        public let kind: Kind
        public let position: Int

        public init(source: SessionReference, id: String, kind: Kind, position: Int) {
            self.source = source
            self.id = id
            self.kind = kind
            self.position = position
        }
    }

    public struct Item: Codable, Equatable, Sendable {
        public let reference: Reference
        public let text: String

        public init(reference: Reference, text: String) {
            self.reference = reference
            self.text = text
        }
    }

    public struct Omission: Codable, Equatable, Sendable {
        public enum Reason: String, Codable, Sendable {
            case budget, reasoning, toolState, attachmentNotReplayed, localNotice
        }
        public let source: SessionReference
        public let id: String
        public let reason: Reason

        public init(source: SessionReference, id: String, reason: Reason) {
            self.source = source
            self.id = id
            self.reason = reason
        }
    }

    public struct Draft: Sendable {
        public var items: [Item]
        public var omitted: [Omission]

        public init(items: [Item], omitted: [Omission] = []) {
            self.items = items
            self.omitted = omitted
        }

        public func after(_ earlier: ContextTransfer?) -> Self {
            guard let earlier else { return self }
            var seen: Set<Reference> = []
            let items = (earlier.items + items).filter { seen.insert($0.reference).inserted }
            return Self(items: items, omitted: earlier.receipt.omitted + omitted)
        }
    }

    public enum Delivery: String, Codable, Sendable {
        case prepared, uncertain, acceptedByHost, agentResponded, notSent
    }

    public struct Receipt: Codable, Equatable, Sendable {
        public let id: UUID
        public var destination: SessionReference
        public let model: String?
        public let plan: AgentTransitionPlan
        public var budget: ContextTransferSelector.Budget
        public var included: [Reference]
        public var omitted: [Omission]
        public var delivery: Delivery = .prepared

        public var summary: String {
            switch delivery {
            case .uncertain:
                "Context delivery is uncertain. It will not be sent again automatically. Open Earlier Conversations to recover it."
            case .notSent:
                "No earlier context fit. Open Earlier Conversations to recover the history."
            case .prepared:
                "\(included.count) context items ready; \(omitted.count) left out. Earlier Conversations keeps the full history."
            case .acceptedByHost:
                "Host accepted \(included.count) context items; \(omitted.count) left out. Agent delivery is not confirmed."
            case .agentResponded:
                "Agent responded after receiving \(included.count) context items; \(omitted.count) left out."
            }
        }
    }

    public var items: [Item]
    public var receipt: Receipt

    public init(
        draft: Draft, destination: SessionReference, model: String?, plan: AgentTransitionPlan,
        budget: ContextTransferSelector.Budget
    ) {
        items = draft.items
        receipt = Receipt(
            id: UUID(), destination: destination, model: model, plan: plan, budget: budget,
            included: draft.items.map(\.reference), omitted: draft.omitted)
        self = ContextTransferSelector.select(self, budget: budget)
    }

    /// Persist this transition before making a request. A recovered attempt cannot be replayed.
    public mutating func beginDelivery(budget: ContextTransferSelector.Budget) -> ContentBlock? {
        guard receipt.delivery == .prepared else { return nil }
        self = ContextTransferSelector.select(self, budget: budget)
        guard let block = ContextTransferSelector.block(for: self) else {
            receipt.delivery = .notSent
            return nil
        }
        receipt.delivery = .uncertain
        return block
    }

    public mutating func acknowledge(_ delivery: Delivery) {
        guard receipt.delivery == .uncertain, delivery == .acceptedByHost || delivery == .agentResponded else { return }
        receipt.delivery = delivery
    }
}
