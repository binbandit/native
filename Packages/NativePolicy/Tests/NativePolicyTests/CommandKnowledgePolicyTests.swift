import ApprovalAnalysis
import Foundation
import Testing

@testable import NativePolicy

@Suite struct CommandKnowledgePolicyTests {
    @Test func organizationCanDisableLocalCounts() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(
                managed: [PolicyKey.unknownCommandCounts.rawValue: false],
                user: [PolicyKey.unknownCommandCounts.rawValue: true]))
        #expect(!policy.unknownCommandCountsEnabled)
        #expect(policy.isManaged(.unknownCommandCounts))
        #expect(PolicyLoader.load(from: StaticPolicySource()).unknownCommandCountsEnabled)
    }

    @Test func knowledgeUsesTheSameValidatedFormat() {
        let json =
            #"{"version":1,"programs":[{"executables":["internal-check"],"commands":[{"words":[],"summary":"check internal state","consequence":"No files changed.","destructive":false,"options":[],"operands":{"minimum":0,"maximum":0,"summary":"argument","paths":false}}]}],"locations":[]}"#
        let policy = PolicyLoader.load(from: StaticPolicySource(managed: [PolicyKey.commandKnowledge.rawValue: json]))
        #expect(policy.isManaged(.commandKnowledge))
        #expect(policy.diagnostics.isEmpty)
        #expect(policy.commandKnowledge.recognizes("internal-check"))
        #expect(
            ApprovalCommand(command: "internal-check", workingDirectory: "/", knowledge: policy.commandKnowledge).risk
                == .routine)
    }

    @Test func invalidKnowledgeHasAClearDiagnostic() {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(managed: [PolicyKey.commandKnowledge.rawValue: "not json"]))
        #expect(
            policy.diagnostics.contains {
                $0.key == PolicyKey.commandKnowledge.rawValue && $0.problem.contains("not valid JSON")
            })
        #expect(!policy.commandKnowledge.recognizes("anything"))
    }
}
