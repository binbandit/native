import Foundation

extension ToolCallState {
    /// A deliberately small vocabulary for answering without opening the request. Unknown tools,
    /// shell syntax, plans and commands with external effects always need the full review surface.
    /// This is shortcut routing, not a claim that executing project code is sandboxed or undoable.
    public var allowsQuickApproval: Bool {
        guard kind != .switchMode, kind != .delete, kind != .move else { return false }
        guard let command = shellCommand else { return kind == .read || kind == .search }
        guard command.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || " _./-".contains($0)) }) else {
            return false
        }
        let words = command.split(separator: " ").map(String.init)
        // Do not infer the behavior of wrappers, absolute binaries, options or compound scripts.
        if words == ["swift", "test"] || words == ["swift", "build"] { return true }
        if words.count == 4, Array(words.prefix(3)) == ["swift", "test", "--filter"],
            !words[3].hasPrefix("-")
        {
            return true
        }
        return words == ["git", "status"] || words == ["git", "status", "--short"]
            || words == ["git", "diff"] || words == ["git", "diff", "--stat"]
    }
}
