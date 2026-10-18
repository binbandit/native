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

    /// A review bot's footer, as it came on binbandit/oh-fx#952.
    @Test func inlineHTMLBecomesMarkdown() {
        let footer = """
            Verified in `3564d00`.

            <!-- PULLFROG_DIVIDER_DO_NOT_REMOVE_PLZ -->
            <sup><a href="https://pullfrog.com"><picture><source media="(prefers-color-scheme: dark)" \
            srcset="https://pullfrog.com/logos/frog-white-full-18px.png"><img \
            src="https://pullfrog.com/logos/frog-green-full-18px.png" width="9px" height="9px" \
            style="vertical-align: middle; " alt="Pullfrog"></picture></a>&nbsp;&nbsp;｜ \
            [View workflow run](https://github.com/binbandit/oh-fx/actions/runs/38208172079) ｜ via \
            [Pullfrog](https://pullfrog.com) ｜ Using `gpt-6.1-sol` ｜ [𝕏](https://x.com/pullfrogai)</sup>
            """
        #expect(
            GitHubMarkdown.displayed(footer) == """
                Verified in `3564d00`.

                  ｜ [View workflow run](https://github.com/binbandit/oh-fx/actions/runs/38208172079) ｜ via \
                [Pullfrog](https://pullfrog.com) ｜ Using `gpt-6.1-sol` ｜ [𝕏](https://x.com/pullfrogai)
                """)
        #expect(
            GitHubMarkdown.displayed(#"See <a href="https://x.dev">the docs</a>."#) == "See [the docs](https://x.dev).")
    }

    @Test func codeKeepsItsHTML() {
        let markdown = """
            Use `<sup>` here, and `Vec<T>`.
            ```html
            <sup><a href="x">y</a></sup>
            ```
            """
        #expect(GitHubMarkdown.displayed(markdown) == markdown)
    }
}
