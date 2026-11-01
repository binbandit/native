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
import MCP
import NativeOrchestration

public struct ToolUseCase: Sendable {
    public enum Kind: String, Sendable { case bad, guardCase = "guard", control }

    public struct Match: Sendable {
        public var tool: String
        public var arguments: [String: JSON]
        public var containing: [String: String]

        public init(_ tool: String, _ arguments: [String: JSON] = [:], containing: [String: String] = [:]) {
            self.tool = tool
            self.arguments = arguments
            self.containing = containing
        }

        public func matches(_ call: EvalTranscript.Call) -> Bool {
            call.tool == tool
                && arguments.allSatisfy { call.arguments[$0.key] == $0.value }
                && containing.allSatisfy {
                    call.arguments[$0.key]?.stringValue?.localizedCaseInsensitiveContains($0.value) == true
                }
        }
    }

    public struct Count: Sendable {
        public var match: Match
        public var minimum: Int
        public var maximum: Int

        public init(_ match: Match, _ minimum: Int = 1, _ maximum: Int = 1) {
            self.match = match
            self.minimum = minimum
            self.maximum = maximum
        }
    }

    public struct Seed: Sendable {
        public var id: String
        public var title: String
        public var status: TaskSnapshot.Status
        public var reply: String?

        public init(_ id: String, _ title: String, status: TaskSnapshot.Status = .running, reply: String? = nil) {
            self.id = id
            self.title = title
            self.status = status
            self.reply = reply
        }
    }

    public var id: String
    public var kind: Kind
    public var prompt: String
    public var agents = ["claude-code", "review-agent"]
    public var seeds: [Seed] = []
    public var isChild = false
    public var counts: [Count] = []
    public var forbidden: [Match] = []
    public var order: [Match] = []
    public var finalContains: [String] = []
    public var finalExcludes: [String] = []

    public init(_ id: String, _ kind: Kind, _ prompt: String) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
    }
}
