-- Session memo, keyed on the question and the exact unit source. Editing one function
-- re-asks that function and nothing else; leaving the buffer alone re-asks nothing.
local M = {}

M.store = {}

local function normalize(question)
  return (vim.trim(question):lower():gsub("%s+", " "))
end

function M.key(question, source)
  return vim.fn.sha256(normalize(question) .. "\0" .. source)
end

function M.get(question, unit)
  return M.store[M.key(question, unit.source)]
end

function M.set(question, unit, p)
  M.store[M.key(question, unit.source)] = p
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
