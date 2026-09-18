-- Quickfix in arrival order, sorted once at the end. Re-sorting per batch would move
-- entries under the cursor while you walk the list, which is the whole workflow the
-- plugin sells, so the final sort only happens if you have not moved yet.
local M = {}

M.title = "jev"
M.entries = {}
M.id = nil

local function item_for(hit, threshold)
  local unit = hit.unit
  local text = ("%.2f  %s"):format(hit.p, unit.name)
  if hit.p < threshold then
    text = text .. "  (below t)"
  end
  local item = { lnum = unit.lnum, col = unit.col + 1, text = text, type = "I" }
  if unit.bufnr and vim.api.nvim_buf_is_valid(unit.bufnr) then
    item.bufnr = unit.bufnr
  else
    item.filename = unit.file
  end
  return item
end

function M.start(question)
  M.entries = {}
  vim.fn.setqflist({}, " ", { title = M.title .. ": " .. question, items = {} })
  -- Pin the list we just made. Batches land over seconds, and anything else that fills
  -- quickfix meanwhile (:grep, LSP references, trouble) would otherwise take our appends
  -- and then our replacing sort.
  M.id = vim.fn.getqflist({ id = 0 }).id
end

--- Our list, if it still exists. It falls off the stack after ten newer ones.
local function ours()
  return M.id and M.id ~= 0 and vim.fn.getqflist({ id = M.id }).id == M.id
end

--- Append one batch, newest last. Cheap enough to call on every response.
function M.append(hits, threshold)
  local items = {}
  for _, hit in ipairs(hits) do
    M.entries[#M.entries + 1] = hit
    items[#items + 1] = item_for(hit, threshold)
  end
  if #items > 0 and ours() then
    vim.fn.setqflist({}, "a", { id = M.id, items = items })
  end
end

function M.sort(threshold)
  table.sort(M.entries, function(a, b)
    if a.p == b.p then
      return a.unit.name < b.unit.name
    end
    return a.p > b.p
  end)
  if not ours() then
    return
  end
  local items = vim.tbl_map(function(hit)
    return item_for(hit, threshold)
  end, M.entries)
  vim.fn.setqflist({}, "r", { id = M.id, items = items })
end

--- True if the cursor is still on the first entry, so a sort is safe.
function M.untouched()
  if not ours() then
    return false
  end
  return (vim.fn.getqflist({ id = M.id, idx = 0 }).idx or 1) <= 1
end

function M.open()
  vim.cmd("botright copen")
  vim.cmd("wincmd p")
end

return M
