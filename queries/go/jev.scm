; Vendored from nvim-treesitter-textobjects queries/go/textobjects.scm (Apache-2.0,
; see NOTICE). A bare func_literal is dropped: every inline closure would become its own
; question, and closures are rarely what a search question is about. One bound to a
; package-level var is kept, because that one has a name and a caller looks it up by it.
(function_declaration) @function.outer

(method_declaration) @function.outer

(var_declaration
  (var_spec
    value: (expression_list (func_literal)))) @function.outer
