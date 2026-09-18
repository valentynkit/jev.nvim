-- Session memo, keyed on the question and the exact unit source. Editing one function
-- re-asks that function and nothing else; leaving the buffer alone re-asks nothing.
local M = {}

M.store = {}

local function normalize(question)
  return (vim.trim(question):lower():gsub("%s+", " "))
end

-- The doc is in the key because it ships to Jev as its own field and, outside python,
-- lives above the slice `source` covers. Without it, editing only the comment over a
-- function replays the old answer, injected instructions included.
-- \1 and not \0 as the separator: a Lua string holding a NUL crosses into Vimscript as a
-- Blob, and sha256() on 0.10 answers E976 rather than hashing it.
function M.key(question, source, doc)
  return vim.fn.sha256(normalize(question) .. "\1" .. source .. "\1" .. (doc or ""))
end

function M.get(question, unit)
  return M.store[M.key(question, unit.source, unit.doc)]
end

function M.set(question, unit, p)
  M.store[M.key(question, unit.source, unit.doc)] = p
end

--- Split units into what we already know and what still needs asking.
function M.split(question, units)
  local known, unknown = {}, {}
  for _, unit in ipairs(units) do
    local p = M.get(question, unit)
    if p then
      known[#known + 1] = { unit = unit, p = p }
    else
      unknown[#unknown + 1] = unit
    end
  end
  return known, unknown
end

function M.clear()
  M.store = {}
end

function M.count()
  return vim.tbl_count(M.store)
end

return M
