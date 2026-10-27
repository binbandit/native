import Foundation
import Testing

@testable import ACP

struct FileMentionMatcherTests {
    private let files = ["README.md", "docs/guide.md", "src/components/Button.tsx", "src/index.ts"]
    private let matcher = FileMentionMatcher(changed: [], recent: [])

    @Test func foldersAreListedBeforeWhatTheyHold() {
        #expect(
            FileMention.entries(forFiles: files) == [
                "README.md", "docs/", "docs/guide.md", "src/", "src/components/", "src/components/Button.tsx",
                "src/index.ts",
            ])
    }

    @Test func aFolderNamedByTheQueryOutranksTheFilesInIt() {
        let entries = FileMention.entries(forFiles: files)
        #expect(matcher.matches(for: "comp", in: entries, limit: 3).first == "src/components/")
        #expect(matcher.matches(for: "src", in: entries, limit: 3).first == "src/")
        // A file named by the query still beats the folder it's in.
        #expect(matcher.matches(for: "button", in: entries, limit: 3).first == "src/components/Button.tsx")
    }

    @Test func typingTheTrailingSlashKeepsTheFolder() {
        let entries = FileMention.entries(forFiles: files)
        #expect(matcher.matches(for: "src/components/", in: entries, limit: 5).contains("src/components/"))
    }

    @Test func dotSlashListsOnlyRootEntriesWithFoldersFirst() {
        let entries = FileMention.entries(forFiles: files + [".config/settings.json", ".gitignore"])
        #expect(
            matcher.matches(for: "./", in: entries, limit: 50) == [
                ".config/", "docs/", "src/", ".gitignore", "README.md",
            ])
    }

    @Test func dotSlashFiltersTheRootByAPartialName() {
        let entries = FileMention.entries(forFiles: files + ["docs-notes.md", "nested/document.md"])
        #expect(matcher.matches(for: "./do", in: entries, limit: 50) == ["docs/", "docs-notes.md"])
    }

    @Test func dotSlashCanBrowseAHiddenFolderWithoutMatchingEveryDot() {
        let entries = FileMention.entries(forFiles: files + [".config/settings.json"])
        #expect(matcher.matches(for: "./.co", in: entries, limit: 50) == [".config/"])
        #expect(matcher.matches(for: "./.config/", in: entries, limit: 50) == [".config/", ".config/settings.json"])
    }

    @Test(arguments: ["../", "./../", "docs/../../", "/", "docs/../src/"])
    func pathsCannotLeaveTheProject(query: String) {
        let entries = FileMention.entries(forFiles: files)
        #expect(matcher.matches(for: query, in: entries, limit: 50).isEmpty)
    }

    @Test func bareAtStillOffersRecentAndChangedFiles() {
        let entries = FileMention.entries(forFiles: files)
        let ranked = FileMentionMatcher(changed: ["docs/guide.md"], recent: ["src/index.ts"])
        #expect(ranked.matches(for: "", in: entries, limit: 2) == ["src/index.ts", "docs/guide.md"])
    }

    @Test func rootBrowsingKeepsFoldersAheadOfRecentFilesAndHonorsTheLimit() {
        let entries = FileMention.entries(forFiles: files)
        let ranked = FileMentionMatcher(changed: ["README.md"], recent: ["README.md"])
        #expect(ranked.matches(for: "./", in: entries, limit: 2) == ["docs/", "src/"])
    }

    @Test func namedFolderBrowsingStaysInThatFolder() {
        let entries = FileMention.entries(forFiles: files + ["docs/nested/detail.md", "other/docs/guide.md"])
        #expect(
            matcher.matches(for: "docs/", in: entries, limit: 50) == [
                "docs/", "docs/nested/", "docs/guide.md",
            ])
    }

    @Test func aMentionedFolderGoesAsALinkToTheFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "mention-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: "src/components"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mentions = PromptAttachment.mentions(in: "look in @src/components/ please", relativeTo: root)
        #expect(mentions.count == 1)
        let blocks = ContentBlock.prompt("x", attachments: mentions, capabilities: PromptCapabilities())
        guard case .resourceLink(let uri, let name) = blocks.last else {
            Issue.record("expected a resource link, got \(blocks)")
            return
        }
        #expect(uri.hasSuffix("/src/components/"))
        #expect(name == "components")
    }
}
