; From tree-sitter/tree-sitter-json v0.24.8, queries/highlights.scm (MIT; see NOTICE.md).
; Changed: keys come after strings, since later patterns win (tree-sitter 0.25).
(string) @string

(pair
  key: (_) @string.special.key)

(number) @number

[
  (null)
  (true)
  (false)
] @constant.builtin

(escape_sequence) @escape

(comment) @comment
