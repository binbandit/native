import Foundation

/// Where a skill is installed from.
public enum SkillInstallSource: Hashable, Sendable, Codable {
    /// A git repository, optionally a branch or tag and a folder inside it.
    case git(url: String, ref: String? = nil, subpath: String? = nil)
    /// A folder on the host.
    case folder(path: String)
    /// A skill in the skills.sh registry: its repository (`owner/repo`) and its id there.
    case registry(source: String, skill: String)

    /// Reads what the user typed or pasted: a path, a git or GitHub URL (including a
    /// `/tree/<ref>/<folder>` link), a skills.sh link, `owner/repo` for GitHub, or
    /// `owner/repo/skill` for a registry skill. `#ref` after a git source picks a branch or tag.
    public static func parse(_ input: String, home: String? = nil) -> SkillInstallSource? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.hasPrefix("/") { return .folder(path: text) }
        if text.hasPrefix("~/"), let home { return .folder(path: SkillPaths.join(home, String(text.dropFirst(2)))) }
        let (base, ref) = splitRef(text)
        if let url = URL(string: base), let host = url.host()?.lowercased(), url.scheme?.hasPrefix("http") == true {
            let parts = url.path(percentEncoded: false).split(separator: "/").map(String.init)
            if host == "skills.sh" || host == "www.skills.sh" {
                guard parts.count == 3 else { return nil }
                return .registry(source: "\(parts[0])/\(parts[1])", skill: parts[2])
            }
            if host == "github.com", parts.count >= 2 {
                let repository =
                    "https://github.com/\(parts[0])/\(parts[1].replacingOccurrences(of: ".git", with: "")).git"
                if parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" {
                    let folder = parts.dropFirst(4).joined(separator: "/")
                    return .git(url: repository, ref: parts[3], subpath: folder.isEmpty ? nil : folder)
                }
                return .git(url: repository, ref: ref)
            }
            return .git(url: base, ref: ref)
        }
        if base.hasPrefix("git@") || base.hasPrefix("ssh://") || base.hasPrefix("git://") || base.hasSuffix(".git") {
            return .git(url: base, ref: ref)
        }
        let parts = base.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy(isRepositoryComponent) else { return nil }
        switch parts.count {
        case 2: return .git(url: "https://github.com/\(parts[0])/\(parts[1]).git", ref: ref)
        case 3 where ref == nil: return .registry(source: "\(parts[0])/\(parts[1])", skill: parts[2])
        default: return nil
        }
    }

    /// In a few words, for the install sheet and the details.
    public var displayText: String {
        switch self {
        case .git(let url, let ref, let subpath):
            [url, ref.map { "#\($0)" }, subpath.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
        case .folder(let path): path
        case .registry(let source, let skill): "skills.sh/\(source)/\(skill)"
        }
    }

    /// Whether getting it needs the network.
    public var isRemote: Bool {
        if case .folder = self { false } else { true }
    }

    private static func splitRef(_ text: String) -> (String, String?) {
        guard let hash = text.lastIndex(of: "#") else { return (text, nil) }
        let ref = String(text[text.index(after: hash)...])
        return (String(text[..<hash]), ref.isEmpty ? nil : ref)
    }

    private static func isRepositoryComponent(_ part: String) -> Bool {
        !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } && part != "."
            && part != ".."
    }
}
