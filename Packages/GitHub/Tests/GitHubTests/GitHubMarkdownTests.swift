import Testing

@testable import GitHub

struct GitHubMarkdownTests {
    @Test func templateCommentsDisappear() {
        let body =
            "Part of #1.\n\n<!--\nThank you for contributing!\n-->\n\nThis adds `download`. <!-- inline --> Done."
        #expect(GitHubMarkdown.removingComments(body) == "Part of #1.\n\nThis adds `download`.  Done.")
    }

    @Test func codeKeepsItsComments() {
        let body = "```html\n<!-- kept -->\n```\n<!-- gone -->"
        #expect(GitHubMarkdown.removingComments(body) == "```html\n<!-- kept -->\n```")
        #expect(
            GitHubMarkdown.removingComments("No comments here.\n\n\nStill three newlines.")
                == "No comments here.\n\n\nStill three newlines.")
    }

    @Test func disclosuresBecomeMarkdown() {
        let body = "diff a...b\n\n<details>\n<summary>React upstream changes</summary>\n\n- one\n</details>"
        #expect(GitHubMarkdown.displayed(body) == "diff a...b\n\n**React upstream changes**\n\n- one")
    }
}
