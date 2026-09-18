; Vendored from nvim-treesitter-textobjects queries/go/textobjects.scm (Apache-2.0,
; see NOTICE). func_literal is dropped: every inline closure would become its own
; question, and closures are rarely what a search question is about.
(function_declaration) @function.outer

(method_declaration) @function.outer
