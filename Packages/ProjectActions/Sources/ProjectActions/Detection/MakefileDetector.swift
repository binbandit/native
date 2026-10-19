import Foundation

/// A Makefile's named targets, as `make <target>`. File targets (`build/app.o`), pattern rules,
/// special targets (`.PHONY`) and variables are left out.
enum MakefileDetector {
    static func detect(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        guard let file = folder.first(of: ["GNUmakefile", "makefile", "Makefile"]), let text = folder.text(file) else {
            return []
        }
        return targets(in: text).map {
            ProjectSuggestion.named($0.name, command: "make \($0.name)", source: .makefile, detail: $0.doc)
        }
    }

    struct Target: Equatable {
        let name: String
        /// A `## comment` after the target, the self-documenting Makefile convention.
        let doc: String?
    }

    static func targets(in text: String) -> [Target] {
        var targets: [Target] = []
        var seen: Set<String> = []
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            // Recipe lines start with a tab; directives and comments aren't rules.
            guard let first = line.first, !first.isWhitespace, first != "#", first != "." else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let after = line[line.index(after: colon)...]
            let prerequisites = after.prefix { $0 != "#" }
            // `x := y`, `x ::= y` and `x:=y` are variables; `a: b = c` sets one for a target.
            if after.hasPrefix("=") || after.hasPrefix(":") || line[..<colon].contains("=")
                || prerequisites.contains("=")
            {
                continue
            }
            let doc = line.range(of: "##").map { line[$0.upperBound...].trimmingCharacters(in: .whitespaces) }
            for name in line[..<colon].split(whereSeparator: \.isWhitespace).map(String.init)
            where isRunnable(name) && seen.insert(name).inserted {
                targets.append(Target(name: name, doc: doc?.isEmpty == false ? doc : nil))
            }
        }
        return targets
    }

    /// A name a person would type: no paths, extensions, patterns or variables.
    private static func isRunnable(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
