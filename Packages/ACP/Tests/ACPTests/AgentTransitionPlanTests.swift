import Foundation
import Testing

@testable import ACP

@Suite struct AgentTransitionPlanTests {
    private func captured() throws -> EffectiveAgentCapabilities {
        let initialized = try Wire.decode(InitializeResponse.self, from: Wire.initializeResult)
        let session = try Wire.decode(NewSessionResponse.self, from: Wire.newSessionResult)
        let options = try #require(session.configOptions)
        return EffectiveAgentCapabilities(negotiated: initialized.agentCapabilities, options: options)
    }

    @Test func capturedNegotiationSeparatesAgentAndNativeEnforcement() throws {
        let capabilities = try captured()
        #expect(capabilities[.resume].support == .supported)
        #expect(capabilities[.resume].enforcement == .agent)
        #expect(capabilities[.model].enforcement == .both)
        #expect(capabilities[.context].enforcement == .native)
        #expect(capabilities[.fork].support == .unsupported)
        #expect(capabilities[.completion].reason == .turnEndOnly)
    }

    @Test func unknownNegotiationDoesNotInventSupport() {
        let target = EffectiveAgentCapabilities(negotiated: nil)
        #expect(target[.resume].support == .unknown)
        #expect(target[.permissions].support == .unknown)
        #expect(AgentTransitionPlan.resolve(.resume, target: target, sameSession: true).action == .createWithHandoff)
        #expect(AgentTransitionPlan.resolve(.fork, target: target).outcome == .refused)
    }

    @Test func exactSelectionsNeverSubstituteAnotherValue() throws {
        let target = try captured()
        let model = AgentTransitionPlan.resolve(.model("opus"), target: target)
        #expect(model.outcome == .exact)
        #expect(model.values == ["model": "opus"])
        #expect(AgentTransitionPlan.resolve(.model("missing"), target: target).reason == .unavailableValue)
        #expect(AgentTransitionPlan.resolve(.options(["missing": "high"]), target: target).reason == .missingOption)
        #expect(AgentTransitionPlan.resolve(.options(["effort": "low"]), target: target).outcome == .exact)
    }

    @Test func matchingAgentNameIsNotContinuationEvidence() throws {
        let target = try captured()
        #expect(AgentTransitionPlan.resolve(.resume, target: target).reason == .incompatibleSession)
        #expect(AgentTransitionPlan.resolve(.resume, target: target, sameSession: true).action == .resume)
        #expect(AgentTransitionPlan.resolve(.reuse, target: target, sameSession: true).action == .reuse)
        let plan = AgentTransitionPlan.resolve(.freshConversation, target: target)
        #expect(plan.outcome == .fallback)
        #expect(plan.action == .createWithHandoff)
        #expect(!plan.explanation.isEmpty)
    }

    @Test func loadReplayIsDisclosedAndFallbackCanBeRefused() throws {
        let response = try Wire.decode(
            InitializeResponse.self, from: #"{"protocolVersion":1,"agentCapabilities":{"loadSession":true}}"#)
        let target = EffectiveAgentCapabilities(negotiated: response.agentCapabilities)
        #expect(target[.resume].support == .unsupported)
        #expect(AgentTransitionPlan.resolve(.resume, target: target, sameSession: true).action == .loadWithReplay)
        #expect(
            AgentTransitionPlan.resolve(.resume, target: target, sameSession: true, allowsFallback: false).outcome
                == .refused)
    }

    @Test func pluginSteeringKeepsToolBoundarySemantics() throws {
        let target = try captured()
        #expect(AgentTransitionPlan.resolve(.steer, target: target).action == .steerAfterTools)
        let immediate = EffectiveAgentCapabilities(negotiated: target.negotiated, steeringPolicy: .nonInterrupting)
        #expect(AgentTransitionPlan.resolve(.steer, target: immediate).outcome == .exact)
        let emulated = EffectiveAgentCapabilities(negotiated: nil, steeringPolicy: .afterTools)
        #expect(emulated[.steering].enforcement == .native)
        #expect(AgentTransitionPlan.resolve(.steer, target: emulated).action == .interruptAfterTools)
    }

    @Test func permissionPlansUseExistingConservativeTranslator() throws {
        let target = try captured()
        let equivalent = AgentTransitionPlan.resolve(.permissions(source: "auto", forbidden: []), target: target)
        #expect(equivalent.outcome == .exact)
        let narrowed = AgentTransitionPlan.resolve(
            .permissions(source: "full-access", forbidden: ["bypassPermissions"]), target: target)
        #expect(narrowed.reason == .stricterPermission)
        #expect(narrowed.values == ["mode": "auto"])
        let unknown = AgentTransitionPlan.resolve(.permissions(source: "foreign-mode", forbidden: []), target: target)
        #expect(unknown.outcome == .fallback)
        #expect(unknown.reason == .incomparablePermissions)
        let denied = AgentTransitionPlan.resolve(
            .permissions(
                source: "auto",
                forbidden: Set(
                    target.options.flatMap { option in
                        if case .select(_, let choices) = option.kind { return choices.map(\.value) }
                        return []
                    })), target: target)
        #expect(denied.reason == .noSafePermissions)
    }

    @Test func pluginMappingsRespectForbiddenWireValues() throws {
        let captured = try captured()
        let mode = try #require(captured.options.first { $0.category == "mode" })
        let presented = TaskPermissionMapping.standard.presenting(mode)
        let target = EffectiveAgentCapabilities(negotiated: captured.negotiated, options: [presented])
        let plan = AgentTransitionPlan.resolve(
            .permissions(source: "full-access", forbidden: ["bypassPermissions"]), target: target)
        #expect(plan.reason == .stricterPermission)
        #expect(plan.values["mode"] != "full-access")
    }

    @Test func pluginStandInsRemainFallbacksAndCanBeRefused() throws {
        let raw = try Wire.decode(
            ConfigOption.self,
            from:
                #"{"id":"mode","name":"Mode","category":"mode","type":"select","currentValue":"manual-wire","options":[{"value":"manual-wire","name":"Manual"},{"value":"edit-wire","name":"Edits"}]}"#
        )
        let mapping = TaskPermissionMapping(values: [.askFirst: ["manual-wire"], .acceptEdits: ["edit-wire"]])
        let target = EffectiveAgentCapabilities(negotiated: nil, options: [mapping.presenting(raw)])
        let plan = AgentTransitionPlan.resolve(.permissions(source: "auto", forbidden: []), target: target)
        #expect(plan.outcome == .fallback)
        #expect(plan.reason == .stricterPermission)
        #expect(plan.values == ["mode": "auto"])
        let restricted = AgentTransitionPlan.resolve(
            .permissions(source: "auto", forbidden: ["accept-edits"]), target: target)
        #expect(restricted.values == ["mode": "ask-first"])
        let refused = AgentTransitionPlan.resolve(
            .permissions(source: "auto", forbidden: []), target: target, allowsFallback: false)
        #expect(refused.outcome == .refused)
        #expect(refused.reason == .fallbackDisabled)
        #expect(
            AgentTransitionPlan.resolve(.permissions(source: "accept-edits", forbidden: []), target: target).outcome
                == .exact)
    }

    @Test func pluginMappingsPreserveRecognizedSourceAliasesWithoutBroadMigration() throws {
        let captured = try captured()
        var mode = try #require(captured.options.first { $0.category == "mode" })
        if case .select(let current, let choices) = mode.kind {
            mode.kind = .select(
                currentValue: current, options: choices.filter { $0.value != "plan" && $0.value != "read-only" })
        }
        let target = EffectiveAgentCapabilities(
            negotiated: captured.negotiated, options: [TaskPermissionMapping.standard.presenting(mode)])
        for source in ["default", "acceptEdits", "agent", "bypassPermissions", "agent-full-access"] {
            let plan = AgentTransitionPlan.resolve(
                .permissions(source: source, forbidden: []), target: target, allowsFallback: false)
            #expect(plan.outcome == .exact, "Recognized alias: \(source)")
            #expect(plan.reason == .permissionEquivalent)
        }
        for source in ["plan", "read-only", "workspace-write", "dontAsk", "unknown"] {
            let plan = AgentTransitionPlan.resolve(
                .permissions(source: source, forbidden: []), target: target, allowsFallback: false)
            #expect(plan.outcome == .refused, "Distinct control: \(source)")
        }
    }

    @Test func admissionAndReceiptRoundTrip() throws {
        let target = try captured()
        #expect(AgentTransitionPlan.resolve(.model("opus"), target: target, available: false).reason == .unavailable)
        #expect(AgentTransitionPlan.resolve(.resume, target: target, policyAllows: false).reason == .policyDenied)
        let plan = AgentTransitionPlan.resolve(.freshConversation, target: target)
        #expect(try JSONDecoder().decode(AgentTransitionPlan.self, from: JSONEncoder().encode(plan)) == plan)
    }
}
