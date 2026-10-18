; From tree-sitter/tree-sitter-html v0.23.2, queries/highlights.scm (MIT; see NOTICE.md).
; Changed: an attribute value's quotes are part of the string (appended at the end).
(tag_name) @tag
(erroneous_end_tag_name) @tag.error
(doctype) @constant
(attribute_name) @attribute
(attribute_value) @string
(comment) @comment

[
  "<"
  ">"
  "</"
  "/>"
] @punctuation.bracket

(quoted_attribute_value) @string
