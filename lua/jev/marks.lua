-- The probability, as virtual text at the end of the function's signature line, for
-- every hit at or above the threshold. Cleared by the next :Jev and by :JevClear.
local M = {}

M.ns = vim.api.nvim_create_namespace("jev")
M.marked = {}

function M.setup_highlights()
  vim.api.nvim_set_hl(0, "JevHit", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "JevFaint", { link = "Comment", default = true })
end

-- Exact path match, not vim.fn.bufnr(): that one substring-matches, so a glob unit from
-- errors.py lands its probability on an open vendor/errors.py.
local function buffer_for(unit)
  if unit.bufnr and vim.api.nvim_buf_is_loaded(unit.bufnr) then
    return unit.bufnr
  end
  if unit.file == "" then
    return
  end
  local full = vim.fn.fnamemodify(unit.file, ":p")
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) == full then
      return bufnr
    end
  end
end

function M.place(hit, threshold)
  if hit.p < threshold then
    return
  end
  local bufnr = buffer_for(hit.unit)
  if not bufnr then
    return
  end
  local line = (hit.unit.sig_lnum or hit.unit.lnum) - 1
  if line < 0 or line >= vim.api.nvim_buf_line_count(bufnr) then
    return
  end
  M.marked[bufnr] = true
  pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, line, 0, {
    virt_text = { { ("  %.2f jev"):format(hit.p), hit.p >= 0.9 and "JevHit" or "JevFaint" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
end

function M.clear()
  for bufnr in pairs(M.marked) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
    end
  end
  M.marked = {}
end

--- Every extmark the plugin owns, for the specs.
function M.list(bufnr)
  return vim.api.nvim_buf_get_extmarks(bufnr, M.ns, 0, -1, { details = true })
end

return M
