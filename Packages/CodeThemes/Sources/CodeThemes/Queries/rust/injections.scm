; From tree-sitter/tree-sitter-rust v0.24.2, queries/injections.scm (MIT; see NOTICE.md).
((macro_invocation
  (token_tree) @injection.content)
 (#set! injection.language "rust")
 (#set! injection.include-children))

((macro_rule
  (token_tree) @injection.content)
 (#set! injection.language "rust")
 (#set! injection.include-children))
