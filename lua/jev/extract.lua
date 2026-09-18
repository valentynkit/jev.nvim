-- Treesitter function extraction. One entry point, `from_string`; buffers and glob
-- files are both callers of it, so an unsaved buffer and a file on disk go through
-- exactly the same code.
local M = {}

-- every extract.py:28 measured ~1500 tokens at this cut; longer bodies are distractors.
M.max_source = 3450
M.max_signature = 200

local by_filetype = {
  lua = "lua",
  python = "python",
  rust = "rust",
  go = "go",
  javascript = "javascript",
  javascriptreact = "javascript",
  typescript = "typescript",
  typescriptreact = "tsx",
}

local by_extension = {
  lua = "lua",
  py = "python",
  rs = "rust",
  go = "go",
  js = "javascript",
  mjs = "javascript",
  cjs = "javascript",
  jsx = "javascript",
  ts = "typescript",
  mts = "typescript",
  tsx = "tsx",
}

M.languages = { "lua", "python", "rust", "go", "javascript", "typescript", "tsx" }

--- Language for a path, preferring an already-resolved filetype.
function M.lang_for(path, filetype)
  if filetype and by_filetype[filetype] then
    return by_filetype[filetype]
  end
  return by_extension[(path or ""):match("%.([%w]+)$") or ""]
end

local function field_name(node, text)
  local f = node:field("name")[1]
  return f and vim.treesitter.get_node_text(f, text) or nil
end

-- A name field on the node, else on a child (python's decorated_definition, JS exports),
-- else on an ancestor (an arrow function bound to a variable).
local function name_of(node, text)
  local n = field_name(node, text)
  if n then
    return n
  end
  for child in node:iter_children() do
    if child:named() then
      n = field_name(child, text)
      if n then
        return n
      end
    end
  end
  local parent = node:parent()
  for _ = 1, 2 do
    if not parent then
      break
    end
    n = field_name(parent, text)
    if n then
      return n
    end
    parent = parent:parent()
  end
end

local comment_start = { "^//", "^%-%-", "^#", "^%*", "^/%*", "^;" }

local function is_comment(line)
  for _, pat in ipairs(comment_start) do
    if line:match(pat) then
      return true
    end
  end
  return false
end

-- Signature is the first line that is neither blank, a comment, nor a decorator.
local function signature_of(lines, first)
  for i = first, #lines do
    local t = vim.trim(lines[i])
    if t ~= "" and not t:match("^@") and not is_comment(t) then
      return t:sub(1, M.max_signature), i
    end
  end
  return vim.trim(lines[first] or ""), first
end

-- ponytail: doc is the python docstring or the comment block directly above, nothing
-- else. Ceiling: no javadoc/rustdoc attribute parsing, no doc comments after the
-- signature. Upgrade path is a per-language capture in the query.
local function doc_of(lines, start_line, lang, source)
  if lang == "python" then
    local d = source:match('\n%s*"""(.-)"""') or source:match("\n%s*'''(.-)'''")
    if d then
      return vim.trim(d):sub(1, 400)
    end
  end
  local acc = {}
  local i = start_line - 1
  while i >= 1 and #acc < 5 do
    local t = vim.trim(lines[i])
    if not is_comment(t) then
      break
    end
    table.insert(acc, 1, t)
    i = i - 1
  end
  return table.concat(acc, " "):sub(1, 400)
end

--- Split `text` into judgeable functions.
--- @return table[] units, string? err
function M.from_string(text, lang, path)
  if not lang then
    return {}, ("no language mapping for %s"):format(path or "this buffer")
  end
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
  if not ok or not parser then
    return {}, ("no treesitter parser for %s (run :TSInstall %s)"):format(lang, lang)
  end
  local got, query = pcall(vim.treesitter.query.get, lang, "jev")
  if not got or not query then
    return {}, ("no usable jev query for %s"):format(lang)
  end

  local tree = parser:parse(true)[1]
  local lines = vim.split(text, "\n", { plain = true })
  local widest = {}
  for id, node in query:iter_captures(tree:root(), text, 0, -1) do
    if query.captures[id] == "function.outer" then
      local srow, _, erow, ecol = node:range()
      -- A decorated or exported function matches twice, once with the wrapper and once
      -- without. Same end, so keep whichever starts earlier.
      local key = erow .. ":" .. ecol
      local prev = widest[key]
      if not prev or srow < select(1, prev:range()) then
        widest[key] = node
      end
    end
  end

  local units = {}
  for _, node in pairs(widest) do
    local srow, scol, erow = node:range()
    local sig, sig_line = signature_of(lines, srow + 1)
    local source = table.concat(vim.list_slice(lines, srow + 1, erow + 1), "\n")
    local truncated = #source > M.max_source
    units[#units + 1] = {
      file = path or "",
      lang = lang,
      name = name_of(node, text) or ("anonymous@" .. (srow + 1)),
      signature = sig,
      doc = doc_of(lines, srow + 1, lang, source),
      source = truncated and (source:sub(1, M.max_source) .. "\n[truncated]") or source,
      truncated = truncated,
      lnum = srow + 1,
      col = scol,
      end_lnum = erow + 1,
      sig_lnum = sig_line,
    }
  end
  table.sort(units, function(a, b)
    return a.lnum < b.lnum
  end)
  for _, u in ipairs(units) do
    u.id = ("%s:%d:%s"):format(u.file, u.lnum, u.name)
  end
  return units, nil
end

--- Current buffer text, unsaved edits included.
function M.from_buf(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local path = vim.api.nvim_buf_get_name(bufnr)
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local name = path ~= "" and vim.fn.fnamemodify(path, ":.") or "[No Name]"
  local units, err = M.from_string(text, M.lang_for(path, vim.bo[bufnr].filetype), name)
  for _, u in ipairs(units) do
    u.bufnr = bufnr
  end
  return units, err
end

--- File bytes on disk, never loaded as a buffer.
function M.from_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}, ("cannot read %s"):format(path)
  end
  return M.from_string(table.concat(lines, "\n"), M.lang_for(path), vim.fn.fnamemodify(path, ":."))
end

return M
