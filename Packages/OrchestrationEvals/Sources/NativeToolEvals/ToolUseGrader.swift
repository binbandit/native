// Adapted behavioral case and grading concepts.
//
// MIT License
//
// Copyright (c) 2026 T3 Tools Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
import Foundation
import MCP

public enum ToolUseGrader {
    public struct Grade: Codable, Sendable {
        public enum Outcome: String, Codable, Sendable { case passed, failed, infrastructureError }
        public var outcome: Outcome
        public var failures: [String]
    }

    public static func grade(_ trace: EvalTranscript, against test: ToolUseCase, declarations: [JSON]) -> Grade {
        guard trace.caseID == test.id, trace.completion != .infrastructureError else {
            return Grade(outcome: .infrastructureError, failures: ["Case mismatch or incomplete infrastructure run"])
        }
        var failures: [String] = []
        if trace.completion != .complete { failures.append("Run reached its step limit") }
        if trace.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append("Missing final answer")
        }
        for (index, call) in trace.calls.enumerated() {
            guard let schema = declarations.first(where: { $0["name"]?.stringValue == call.tool })?["inputSchema"]
            else {
                failures.append("Call \(index): unknown tool \(call.tool)")
                continue
            }
            failures += ToolInputValidation.failures(call.arguments, schema: schema).map { "Call \(index): \($0)" }
        }
        for rule in test.counts {
            // Attempts count toward maxima, but failed calls cannot satisfy required behavior.
            let attempts = trace.calls.filter { rule.match.matches($0) }
            let successes = attempts.filter(\.succeeded)
            if successes.count < rule.minimum || attempts.count > rule.maximum {
                failures.append(
                    "\(rule.match.tool): expected \(rule.minimum)...\(rule.maximum), got \(successes.count) successful / \(attempts.count) attempted"
                )
            }
        }
        for rule in test.forbidden where trace.calls.contains(where: rule.matches) {
            failures.append("Forbidden call: \(rule.tool)")
        }
        var cursor = 0
        for rule in test.order {
            guard
                let next = trace.calls.indices.dropFirst(cursor).first(where: {
                    rule.matches(trace.calls[$0]) && trace.calls[$0].succeeded
                })
            else {
                failures.append("Missing ordered call: \(rule.tool)")
                break
            }
            cursor = next + 1
        }
        for text in test.finalContains where !trace.finalText.localizedCaseInsensitiveContains(text) {
            failures.append("Final answer missing: \(text)")
        }
        for text in test.finalExcludes where trace.finalText.localizedCaseInsensitiveContains(text) {
            failures.append("Final answer must exclude: \(text)")
        }
        return Grade(outcome: failures.isEmpty ? .passed : .failed, failures: failures)
    }
}
