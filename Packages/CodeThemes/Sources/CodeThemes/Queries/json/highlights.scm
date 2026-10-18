; From tree-sitter/tree-sitter-json v0.24.8, queries/highlights.scm (MIT; see NOTICE.md).
(pair
  key: (_) @string.special.key)

(string) @string

(number) @number

[
  (null)
  (true)
  (false)
] @constant.builtin

(escape_sequence) @escape

(comment) @comment
