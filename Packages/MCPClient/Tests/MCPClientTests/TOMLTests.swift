import MCPClient
import Testing

@Suite("TOML")
struct TOMLTests {
    @Test func readsTablesAndDottedHeaders() throws {
        let document = try TOML.parse("""
        title = "x"
        [mcp_servers.linear]
        url = "https://mcp.linear.app/mcp"
        [mcp_servers.linear.tools.save_issue]
        approval_mode = "approve"
        [projects."/Users/someone/My Project"]
        trust_level = "trusted"
        """)
        #expect(document["title"] == .string("x"))
        #expect(document["mcp_servers"]?["linear"]?["url"] == .string("https://mcp.linear.app/mcp"))
        #expect(document["mcp_servers"]?["linear"]?["tools"]?["save_issue"]?["approval_mode"] == .string("approve"))
        #expect(document["projects"]?["/Users/someone/My Project"]?["trust_level"] == .string("trusted"))
    }

    @Test func readsValues() throws {
        let document = try TOML.parse(#"""
        basic = "tab\t\"q\" \u00e9"
        literal = 'C:\path'
        multi = """
        one \
          two"""
        raw = '''
        keep \n this'''
        numbers = [1_000, 0x1F, -3, 2.5, 1e3, inf]
        flags = { on = true, off = false, nested.deep = "yes" }
        when = 1979-05-27T07:32:00Z
        day = 1979-05-27 07:32:00
        list = [
          "a", # first
          "b",
        ]
        dotted.key = 4
        """#)
        #expect(document["basic"] == .string("tab\t\"q\" é"))
        #expect(document["literal"] == .string(#"C:\path"#))
        #expect(document["multi"] == .string("one two"))
        #expect(document["raw"] == .string(#"keep \n this"#))
        #expect(document["numbers"] == .array([.integer(1000), .integer(31), .integer(-3), .float(2.5), .float(1000), .float(.infinity)]))
        #expect(document["flags"]?["on"] == .bool(true))
        #expect(document["flags"]?["nested"]?["deep"] == .string("yes"))
        #expect(document["when"] == .dateTime("1979-05-27T07:32:00Z"))
        #expect(document["day"] == .dateTime("1979-05-27 07:32:00"))
        #expect(document["list"] == .array([.string("a"), .string("b")]))
        #expect(document["dotted"]?["key"] == .integer(4))
    }

    @Test func readsArraysOfTables() throws {
        let document = try TOML.parse("""
        [[hooks]]
        name = "a"
        [[hooks]]
        name = "b"
        [hooks.options]
        fast = true
        """)
        #expect(document["hooks"] == .array([
            .table(["name": .string("a")]),
            .table(["name": .string("b"), "options": .table(["fast": .bool(true)])]),
        ]))
    }

    @Test func reportsTheLineOfAnError() {
        #expect(throws: TOMLError(line: 3, message: "\"a\" is defined twice.")) {
            try TOML.parse("a = 1\n\na = 2")
        }
        #expect(throws: TOMLError.self) { try TOML.parse("key = \"unterminated") }
        #expect(throws: TOMLError.self) { try TOML.parse("[table]\n[table]") }
        #expect(throws: TOMLError.self) { try TOML.parse("key = value") }
    }

    @Test func readsTheCodexFixture() throws {
        let text = String(decoding: Fixture.data("codex-config.toml"), as: UTF8.self)
        let document = try TOML.parse(text)
        #expect(document["mcp_servers"]?.tableValue?.keys.sorted() == ["docs", "inspector", "tracker"])
        #expect(document["mcp_servers"]?["inspector"]?["startup_timeout_sec"] == .integer(30))
    }
}
