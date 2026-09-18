; Vendored from nvim-treesitter-textobjects queries/lua/textobjects.scm (Apache-2.0,
; see NOTICE). Own query group so the plugin never depends on that repo's 0.12 floor.
; Bare (function_definition) is narrowed the same way the ecma queries narrow arrows:
; a function is a unit when something binds a name to it, not when it is an argument.
(function_declaration) @function.outer

(assignment_statement
  (expression_list
    (function_definition))) @function.outer

(variable_declaration
  (assignment_statement
    (expression_list
      (function_definition)))) @function.outer

(field
  value: (function_definition)) @function.outer
