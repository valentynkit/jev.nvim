; Vendored from nvim-treesitter-textobjects queries/lua/textobjects.scm (Apache-2.0,
; see NOTICE). Own query group so the plugin never depends on that repo's 0.12 floor.
[
  (function_declaration)
  (function_definition)
] @function.outer
