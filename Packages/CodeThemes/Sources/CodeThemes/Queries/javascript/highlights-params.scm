; From tree-sitter/tree-sitter-javascript v0.23.1, queries/highlights-params.scm (MIT; see NOTICE.md).
(formal_parameters
  [
    (identifier) @variable.parameter
    (array_pattern
      (identifier) @variable.parameter)
    (object_pattern
      [
        (pair_pattern value: (identifier) @variable.parameter)
        (shorthand_property_identifier_pattern) @variable.parameter
      ])
  ]
)
