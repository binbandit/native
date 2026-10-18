import Testing

@testable import Skills

struct SkillDocumentTests {
    @Test func readsTheSpecFieldsAndAgentExtensions() {
        let document = SkillDocument.parse(
            """
            ---
            name: pdf-tools
            description: "Extract text: tables, forms and more. Use for PDFs."
            license: Apache-2.0
            compatibility: Needs python3
            allowed-tools: Read Bash(python3:*)
            user-invocable: false
            disable-model-invocation: true
            metadata:
              author: someone
              version: "1.2"
            ---
            # PDF tools
            """, folderName: "pdf-tools")
        let frontmatter = document.frontmatter
        #expect(frontmatter.name == "pdf-tools")
        #expect(frontmatter.description == "Extract text: tables, forms and more. Use for PDFs.")
        #expect(frontmatter.license == "Apache-2.0")
        #expect(frontmatter.allowedTools == ["Read", "Bash(python3:*)"])
        #expect(frontmatter.isUserInvocable == false)
        #expect(frontmatter.isModelInvocable == false)
        #expect(frontmatter.metadata == ["author": "someone", "version": "1.2"])
        #expect(frontmatter.version == "1.2")
        #expect(document.body == "# PDF tools")
        #expect(document.problems.isEmpty)
    }

    @Test func foldsBlockScalarsAndReadsBlockLists() {
        let document = SkillDocument.parse(
            """
            ---
            name: review
            description: >
              Reviews a diff for bugs.
              Use before merging.
            allowed-tools:
            - Read
            - Grep
            notes: |
              line one
              line two
            ---
            """)
        #expect(document.frontmatter.description == "Reviews a diff for bugs. Use before merging.")
        #expect(document.frontmatter.allowedTools == ["Read", "Grep"])
        #expect(document.frontmatter.otherKeys == ["notes"])
        #expect(document.problems.isEmpty)
    }

    @Test func reportsWhatsWrongWithABrokenSkill() {
        #expect(SkillDocument.parse("# Just markdown").problems == [.noFrontmatter])
        #expect(SkillDocument.parse("---\nname: x\n").problems == [.noFrontmatter])

        let malformed = SkillDocument.parse("---\nname: x\n  stray: indent\n---\n")
        #expect(malformed.problems.count == 1)
        #expect(malformed.problems.first?.severity == .error)

        let missing = SkillDocument.parse("---\nlicense: MIT\n---\nbody")
        #expect(missing.problems == [.missingName, .missingDescription])

        let invalid = SkillDocument.parse("---\nname: My Skill\ndescription: d\n---\n", folderName: "my-skill")
        #expect(
            invalid.problems == [
                .invalidName("My Skill"), .nameDiffersFromFolder(name: "My Skill", folder: "my-skill"),
            ])
        #expect(invalid.problems.allSatisfy { $0.severity == .warning })
    }

    @Test func checksNamesLikeTheSpec() {
        #expect(SkillDocument.isValidName("pdf-tools"))
        #expect(SkillDocument.isValidName("a1"))
        #expect(!SkillDocument.isValidName("-pdf"))
        #expect(!SkillDocument.isValidName("pdf--tools"))
        #expect(!SkillDocument.isValidName("PDF"))
        #expect(!SkillDocument.isValidName(String(repeating: "a", count: 65)))
    }

    @Test func keepsColonsInValuesAndCommentsOut() {
        let document = SkillDocument.parse(
            """
            ---
            name: web # the name
            description: 'Fetch https://example.com pages; it''s fast'
            ---
            """)
        #expect(document.frontmatter.name == "web")
        #expect(document.frontmatter.description == "Fetch https://example.com pages; it's fast")
    }
}
