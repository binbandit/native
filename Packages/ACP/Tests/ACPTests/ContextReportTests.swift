import Foundation
import Testing
@testable import ACP

struct ContextReportTests {
    @Test func parsesTheCapturedReport() throws {
        let report = try #require(ContextReport.parse(ContextCapture.markdown))
        #expect(report.model == "claude-opus-5-5")
        #expect(report.usedTokens == 228_400)
        #expect(report.windowTokens == 1_000_000)
        #expect(report.percentage == 23)
        #expect(report.overLimit == nil)

        #expect(report.categories.map(\.name) == [
            "System prompt", "System tools", "MCP tools", "MCP server instructions", "Memory files", "Skills", "Messages",
            "Free space", "Autocompact buffer",
        ])
        #expect(report.categories.map(\.tokens) == [2_100, 23_100, 197_100, 103, 2_000, 4_000, 10, 738_600, 33_000])
        #expect(report.usedCategories.count == 7)
        #expect(report.freeTokens == 738_600)
        #expect(report.bufferTokens == 33_000)
        #expect(report.deferredCategories.isEmpty)

        #expect(report.mcpTools.count == 170)
        let servers = report.mcpServers
        #expect(servers.map(\.name) == ["rea"])
        #expect(servers.first?.tokens == 197_288)
        #expect(servers.first?.tools.prefix(3).map(\.shortName) == ["compare_web_captures", "evaluate_reconstruction_coverage", "build_reconstruction_obligation_ledger"])
        #expect(servers.first?.tools.first?.tokens == 26_200)

        #expect(report.memoryFiles == [
            ContextReport.MemoryFile(type: "User", path: "/Users/brayden/.claude/CLAUDE.md", tokens: 24),
            ContextReport.MemoryFile(type: "User", path: "/Users/brayden/AGENTS.md", tokens: 2_000),
        ])

        #expect(report.skills.count == 33)
        #expect(report.skills.first == ContextReport.Skill(name: "anatomy", source: "User", tokens: .init(300, bound: .approximate)))
        let codeReview = try #require(report.skills.first { $0.name == "code-review:code-review" })
        #expect(codeReview.source == "Plugin (code-review)")
        #expect(codeReview.tokens == .init(20, bound: .below))
        #expect(report.agents.isEmpty)
    }

    /// The adapter sent the report twice in one turn, as two messages; the second ends in a blank line.
    @Test func reportSentTwiceParsesOnce() throws {
        let doubled = ContextCapture.markdown + ContextCapture.markdown + "\n\n"
        let once = try #require(ContextReport.parse(ContextCapture.markdown, capturedAt: .distantPast))
        let twice = try #require(ContextReport.parse(doubled, capturedAt: .distantPast))
        #expect(twice == once)
    }

    @Test func readsCompactTokenCounts() {
        let cases: [(String, ContextReport.TokenCount?)] = [
            ("103", .init(103)),
            ("2k", .init(2_000)),
            ("228.4k", .init(228_400)),
            ("1m", .init(1_000_000)),
            ("1.5M", .init(1_500_000)),
            ("1,234", .init(1_234)),
            ("~300", .init(300, bound: .approximate)),
            ("< 20", .init(20, bound: .below)),
            (" 7 ", .init(7)),
            ("", nil),
            ("k", nil),
            ("12%", nil),
            ("lots", nil),
        ]
        for (text, expected) in cases {
            #expect(ContextReport.tokenCount(text) == expected, "\(text)")
        }
    }

    @Test func toleratesMissingSectionsAndReadsKinds() throws {
        let markdown = """
        ## Context Usage

        **Model:** claude-sonnet-4-6
        **Tokens:** 212k / 200k (106%)
        **Over limit:** Context exceeds the 200k-token limit by 12k tokens — run /compact or /clear to continue.

        ### Estimated usage by category

        | Category | Tokens | Percentage |
        |----------|--------|------------|
        | System prompt | 3k | 1.5% |
        | MCP tools (deferred) | 41.2k | 20.6% |
        | Messages | 209k | 104.5% |
        | Autocompact buffer | 33k | 16.5% |

        ### Custom Agents

        | Agent Type | Source | Tokens |
        |------------|--------|--------|
        | reviewer | Project | 412 |
        """
        let report = try #require(ContextReport.parse(markdown))
        #expect(report.model == "claude-sonnet-4-6")
        #expect(report.percentage == 106)
        #expect(report.overLimit?.hasPrefix("Context exceeds") == true)
        #expect(report.categories.map(\.kind) == [.used, .deferred, .used, .buffer])
        #expect(report.freeTokens == 0)
        #expect(report.mcpTools.isEmpty && report.memoryFiles.isEmpty && report.skills.isEmpty)
        #expect(report.agents == [ContextReport.CustomAgent(type: "reviewer", source: "Project", tokens: 412)])
    }

    @Test func groupsToolsByServer() throws {
        let markdown = """
        **Tokens:** 10k / 200k (5%)

        ### MCP Tools

        | Tool | Server | Tokens |
        |------|--------|--------|
        | mcp__linear__list_issues | linear | 900 |
        | mcp__claude_ai_Gmail__search | claude.ai Gmail | 2.1k |
        | mcp__linear__create_issue | linear | 1.5k |
        """
        let report = try #require(ContextReport.parse(markdown))
        #expect(report.mcpServers.map(\.name) == ["linear", "claude.ai Gmail"])
        #expect(report.mcpServers.map(\.tokens) == [2_400, 2_100])
        #expect(report.mcpServers.first?.tools.map(\.shortName) == ["create_issue", "list_issues"])
        #expect(report.mcpServers.last?.tools.map(\.shortName) == ["search"])
    }

    @Test func otherTextIsNotAReport() {
        #expect(ContextReport.parse("") == nil)
        #expect(ContextReport.parse("Here's what I found in the repo.") == nil)
        #expect(ContextReport.parse("## Context Usage\n\nNothing to see.") == nil)
    }
}

/// Claude Code's answer to `/context`, captured from `@agentclientprotocol/claude-agent-acp` 0.93.0
/// (`/tmp/acp-research/probe/wire-context.jsonl`): one of the two identical messages it sent.
private enum ContextCapture {
    static let markdown = #"""
## Context Usage

**Model:** claude-opus-5-5  
**Tokens:** 228.4k / 1m (23%)

### Estimated usage by category

| Category | Tokens | Percentage |
|----------|--------|------------|
| System prompt | 2.1k | 0.2% |
| System tools | 23.1k | 2.3% |
| MCP tools | 197.1k | 19.7% |
| MCP server instructions | 103 | 0.0% |
| Memory files | 2k | 0.2% |
| Skills | 4k | 0.4% |
| Messages | 10 | 0.0% |
| Free space | 738.6k | 73.9% |
| Autocompact buffer | 33k | 3.3% |

### MCP Tools

| Tool | Server | Tokens |
|------|--------|--------|
| mcp__rea__address_name | rea | 442 |
| mcp__rea__address_to_file_offset | rea | 563 |
| mcp__rea__analyze_function | rea | 397 |
| mcp__rea__analyze_javascript_application | rea | 1.4k |
| mcp__rea__analyze_swift_types | rea | 762 |
| mcp__rea__analyze_web_bundle | rea | 1.2k |
| mcp__rea__annotate_native_function | rea | 677 |
| mcp__rea__batch_decompile | rea | 361 |
| mcp__rea__binary_overview | rea | 191 |
| mcp__rea__binary_session | rea | 486 |
| mcp__rea__build_call_path | rea | 2.6k |
| mcp__rea__build_reconstruction_obligation_ledger | rea | 7.8k |
| mcp__rea__capture_adb_screen | rea | 486 |
| mcp__rea__capture_browser_scenario | rea | 6.5k |
| mcp__rea__capture_electron_scenario | rea | 1.9k |
| mcp__rea__capture_native_ui_scenario | rea | 1.4k |
| mcp__rea__capture_process_scenario | rea | 3.4k |
| mcp__rea__capture_web_screenshot | rea | 437 |
| mcp__rea__close_binary | rea | 565 |
| mcp__rea__collect_adb_bugreport | rea | 527 |
| mcp__rea__comment | rea | 422 |
| mcp__rea__compare_application_versions | rea | 2.9k |
| mcp__rea__compare_artifacts | rea | 2.5k |
| mcp__rea__compare_bundles | rea | 639 |
| mcp__rea__compare_functions | rea | 2.4k |
| mcp__rea__compare_javascript_export_shapes | rea | 3.2k |
| mcp__rea__compare_managed_members | rea | 2.6k |
| mcp__rea__compare_process_captures | rea | 4.2k |
| mcp__rea__compare_source_to_bundle | rea | 6.3k |
| mcp__rea__compare_web_captures | rea | 26.2k |
| mcp__rea__compare_web_screenshots | rea | 767 |
| mcp__rea__correlate_static_and_runtime | rea | 3.4k |
| mcp__rea__current_address | rea | 307 |
| mcp__rea__current_document | rea | 121 |
| mcp__rea__current_procedure | rea | 291 |
| mcp__rea__decode_android_resources | rea | 760 |
| mcp__rea__decode_interface_builder | rea | 487 |
| mcp__rea__decompile_jeb_item | rea | 605 |
| mcp__rea__demangle_swift | rea | 305 |
| mcp__rea__discover_webmcp_tools | rea | 531 |
| mcp__rea__evaluate_reconstruction_coverage | rea | 9k |
| mcp__rea__export_evidence_bundle | rea | 428 |
| mcp__rea__export_web_scripts | rea | 791 |
| mcp__rea__extract_artifact | rea | 336 |
| mcp__rea__extract_firmware | rea | 1.4k |
| mcp__rea__find_changed_behavior | rea | 2.4k |
| mcp__rea__find_xrefs_to_name | rea | 264 |
| mcp__rea__get_call_graph | rea | 475 |
| mcp__rea__get_evidence_bundle | rea | 695 |
| mcp__rea__get_navigation_context | rea | 278 |
| mcp__rea__get_objc_classes | rea | 218 |
| mcp__rea__get_objc_protocols | rea | 123 |
| mcp__rea__goto_address | rea | 502 |
| mcp__rea__import_evidence_bundle | rea | 348 |
| mcp__rea__import_managed_reconstruction | rea | 3.3k |
| mcp__rea__inline_comment | rea | 410 |
| mcp__rea__inspect_adb_client | rea | 200 |
| mcp__rea__inspect_adb_device | rea | 356 |
| mcp__rea__inspect_adb_display | rea | 310 |
| mcp__rea__inspect_adb_package | rea | 491 |
| mcp__rea__inspect_adb_window | rea | 318 |
| mcp__rea__inspect_address_context | rea | 338 |
| mcp__rea__inspect_analysis_view | rea | 4.4k |
| mcp__rea__inspect_android_class | rea | 448 |
| mcp__rea__inspect_android_method | rea | 635 |
| mcp__rea__inspect_android_package | rea | 338 |
| mcp__rea__inspect_apktool_client | rea | 195 |
| mcp__rea__inspect_artifact | rea | 401 |
| mcp__rea__inspect_asset_catalog | rea | 307 |
| mcp__rea__inspect_binary_layout | rea | 1.1k |
| mcp__rea__inspect_electron_page | rea | 1.2k |
| mcp__rea__inspect_evm_interface | rea | 646 |
| mcp__rea__inspect_firmware_regions | rea | 421 |
| mcp__rea__inspect_jeb_client | rea | 211 |
| mcp__rea__inspect_keyed_archive | rea | 466 |
| mcp__rea__inspect_macho | rea | 170 |
| mcp__rea__inspect_managed_artifact | rea | 421 |
| mcp__rea__inspect_managed_members | rea | 413 |
| mcp__rea__inspect_managed_native_boundaries | rea | 377 |
| mcp__rea__inspect_native_api | rea | 330 |
| mcp__rea__inspect_native_data_type | rea | 366 |
| mcp__rea__inspect_native_dispatch_metadata | rea | 442 |
| mcp__rea__inspect_native_instruction | rea | 345 |
| mcp__rea__inspect_native_load_image | rea | 341 |
| mcp__rea__inspect_pe_resources | rea | 814 |
| mcp__rea__inspect_plist | rea | 255 |
| mcp__rea__inspect_recorded_crash | rea | 789 |
| mcp__rea__inspect_signature | rea | 162 |
| mcp__rea__inspect_web_event_listeners | rea | 603 |
| mcp__rea__inspect_web_network_capture | rea | 1.2k |
| mcp__rea__inspect_web_page | rea | 2.4k |
| mcp__rea__install_adb_package | rea | 634 |
| mcp__rea__list_adb_devices | rea | 229 |
| mcp__rea__list_adb_directory | rea | 460 |
| mcp__rea__list_adb_features | rea | 287 |
| mcp__rea__list_adb_packages | rea | 482 |
| mcp__rea__list_adb_processes | rea | 305 |
| mcp__rea__list_adb_services | rea | 273 |
| mcp__rea__list_architectures | rea | 146 |
| mcp__rea__list_bookmarks | rea | 325 |
| mcp__rea__list_browser_targets | rea | 343 |
| mcp__rea__list_documents | rea | 161 |
| mcp__rea__list_electron_targets | rea | 298 |
| mcp__rea__list_javascript_runtime_targets | rea | 303 |
| mcp__rea__list_jeb_units | rea | 711 |
| mcp__rea__list_names | rea | 422 |
| mcp__rea__list_procedures | rea | 318 |
| mcp__rea__list_segments | rea | 323 |
| mcp__rea__list_strings | rea | 480 |
| mcp__rea__list_unknowns | rea | 383 |
| mcp__rea__next_address | rea | 413 |
| mcp__rea__observe_javascript_runtime | rea | 727 |
| mcp__rea__observe_native_calls | rea | 2k |
| mcp__rea__observe_native_ui | rea | 569 |
| mcp__rea__observe_web_execution | rea | 673 |
| mcp__rea__observe_web_session | rea | 551 |
| mcp__rea__open_binary | rea | 1k |
| mcp__rea__open_jeb_project | rea | 381 |
| mcp__rea__prev_address | rea | 442 |
| mcp__rea__procedure_address | rea | 392 |
| mcp__rea__procedure_assembly | rea | 469 |
| mcp__rea__procedure_callees | rea | 424 |
| mcp__rea__procedure_callers | rea | 408 |
| mcp__rea__procedure_info | rea | 545 |
| mcp__rea__procedure_pseudo_code | rea | 507 |
| mcp__rea__procedure_references | rea | 563 |
| mcp__rea__project_android_application_graph | rea | 2.4k |
| mcp__rea__project_apple_application_graph | rea | 2.5k |
| mcp__rea__project_managed_application_graph | rea | 3k |
| mcp__rea__pull_adb_file | rea | 630 |
| mcp__rea__pull_adb_package | rea | 718 |
| mcp__rea__push_adb_file | rea | 733 |
| mcp__rea__read_adb_logcat | rea | 709 |
| mcp__rea__read_adb_setting | rea | 522 |
| mcp__rea__read_bytes | rea | 523 |
| mcp__rea__read_function_instructions | rea | 368 |
| mcp__rea__reconcile_javascript_runtime | rea | 3k |
| mcp__rea__record_unknown | rea | 1.4k |
| mcp__rea__recover_javascript_sources | rea | 987 |
| mcp__rea__resolve_adb_packages | rea | 491 |
| mcp__rea__resolve_containing_procedure | rea | 482 |
| mcp__rea__resolve_native_call_targets | rea | 310 |
| mcp__rea__search_android_classes | rea | 417 |
| mcp__rea__search_procedures | rea | 599 |
| mcp__rea__search_strings | rea | 791 |
| mcp__rea__set_address_name | rea | 592 |
| mcp__rea__set_addresses_names | rea | 527 |
| mcp__rea__set_bookmark | rea | 496 |
| mcp__rea__set_comment | rea | 529 |
| mcp__rea__set_inline_comment | rea | 534 |
| mcp__rea__start_adb_activity | rea | 1.1k |
| mcp__rea__start_adb_app | rea | 549 |
| mcp__rea__stop_adb_app | rea | 455 |
| mcp__rea__trace_android_references | rea | 572 |
| mcp__rea__trace_application_feature | rea | 3.2k |
| mcp__rea__trace_call_path | rea | 569 |
| mcp__rea__trace_dylib_resolution | rea | 662 |
| mcp__rea__trace_feature | rea | 379 |
| mcp__rea__trace_javascript_semantics | rea | 4.3k |
| mcp__rea__trace_native_ui_action | rea | 706 |
| mcp__rea__trace_native_values | rea | 890 |
| mcp__rea__trace_web_module_imports | rea | 1.1k |
| mcp__rea__trace_web_source_location | rea | 1.1k |
| mcp__rea__uninstall_adb_package | rea | 444 |
| mcp__rea__unset_bookmark | rea | 466 |
| mcp__rea__update_unknown | rea | 1.9k |
| mcp__rea__verify_managed_native_boundaries | rea | 2.5k |
| mcp__rea__verify_reconstruction | rea | 1.2k |
| mcp__rea__verify_unknown_resolution | rea | 316 |
| mcp__rea__xrefs | rea | 469 |

### Memory Files

| Type | Path | Tokens |
|------|------|--------|
| User | /Users/brayden/.claude/CLAUDE.md | 24 |
| User | /Users/brayden/AGENTS.md | 2k |

### Skills

| Skill | Source | Tokens |
|-------|--------|--------|
| anatomy | User | ~300 |
| arena | User | ~110 |
| babysit-pr | User | ~40 |
| bro | User | ~70 |
| code-comments | User | ~100 |
| file-pr | User | ~40 |
| find-skills | User | ~110 |
| frontend-design | User | ~70 |
| herdr | User | ~110 |
| oil-ui-pro | User | ~80 |
| reverse-engineer-anything | User | ~110 |
| review | User | ~70 |
| shadcn | User | ~140 |
| snpm | User | ~100 |
| ultracite | User | ~180 |
| use-codex | User | ~90 |
| use-kite | User | ~160 |
| vercel-react-best-practices | User | ~120 |
| verify | User | ~60 |
| code-review:code-review | Plugin (code-review) | < 20 |
| dataviz | Built-in | ~480 |
| update-config | Built-in | ~240 |
| keybindings-help | Built-in | ~80 |
| code-review | Built-in | ~210 |
| simplify | Built-in | ~60 |
| fewer-permission-prompts | Built-in | ~60 |
| loop | Built-in | ~120 |
| claude-api | Built-in | ~360 |
| workflow-authoring | Built-in | ~80 |
| run | Built-in | ~120 |
| plugin-authoring | Built-in | ~90 |
| init | Built-in | ~20 |
| security-review | Built-in | ~30 |
"""#
}
