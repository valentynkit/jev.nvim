; Vendored from nvim-treesitter-textobjects queries/ecma/textobjects.scm (Apache-2.0,
; see NOTICE). Copied rather than `; inherits: ecma` so each language stands alone.
; Bare (arrow_function) and bare (function_expression) are both narrowed to the places a
; function gets a name: a variable, an object key, a class field. An inline callback is
; not a unit anyone searches for, and the binding is what carries the name.
(function_declaration
  body: (statement_block)) @function.outer

(generator_function_declaration
  body: (statement_block)) @function.outer

(export_statement
  (function_declaration)) @function.outer

(method_definition
  body: (statement_block)) @function.outer

(variable_declarator
  value: [(arrow_function) (function_expression)]) @function.outer

(pair
  value: [(arrow_function) (function_expression)]) @function.outer

; React.forwardRef(props => {...}), React.memo(...), and the (() => {...})() idiom: the
; function sits a level deeper but the declarator still names it. Block bodies only, so
; that a useThing(s => s.value) selector does not become a question of its own.
(variable_declarator
  value: (call_expression
    arguments: (arguments [(arrow_function body: (statement_block)) (function_expression)]))) @function.outer

(variable_declarator
  value: (call_expression
    function: (parenthesized_expression [(arrow_function body: (statement_block)) (function_expression)]))) @function.outer

(public_field_definition
  value: [(arrow_function) (function_expression)]) @function.outer
