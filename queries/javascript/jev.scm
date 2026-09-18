; Vendored from nvim-treesitter-textobjects queries/ecma/textobjects.scm (Apache-2.0,
; see NOTICE). Copied rather than `; inherits: ecma` so each language stands alone.
; Bare (arrow_function) is narrowed to assigned arrows: an inline callback is not a
; unit anyone searches for, and the declarator carries the name.
(function_declaration
  body: (statement_block)) @function.outer

(generator_function_declaration
  body: (statement_block)) @function.outer

(function_expression
  body: (statement_block)) @function.outer

(export_statement
  (function_declaration)) @function.outer

(method_definition
  body: (statement_block)) @function.outer

(variable_declarator
  value: (arrow_function)) @function.outer
