-- One line per extracted function, for eyeballing the queries.
--   nvim --headless -u tests/minimal.lua -l scripts/dump_units.lua fixtures/corpus
local extract = require("jev.extract")
local root = _G.arg[1] or "fixtures/corpus"

local files = vim.fn.glob(root .. "/*", false, true)
table.sort(files)

local total, langs = 0, {}
for _, path in ipairs(files) do
  if vim.fn.isdirectory(path) == 0 then
    local units, err = extract.from_file(path)
    if err then
      print(("%-28s  %s"):format(vim.fn.fnamemodify(path, ":."), err))
    end
    for _, u in ipairs(units) do
      print(("%-22s %-6s %4d  %s"):format(u.file, u.lang, u.lnum, u.name))
      total = total + 1
      langs[u.lang] = (langs[u.lang] or 0) + 1
    end
  end
end

local names = vim.tbl_keys(langs)
table.sort(names)
local parts = {}
for _, l in ipairs(names) do
  parts[#parts + 1] = ("%s=%d"):format(l, langs[l])
end
print(("\n%d functions in %d languages (%s)"):format(total, #names, table.concat(parts, " ")))

local labels_path = vim.fn.fnamemodify(root, ":h") .. "/labels.json"
if vim.fn.filereadable(labels_path) == 1 then
  local labels = vim.json.decode(table.concat(vim.fn.readfile(labels_path), "\n"))
  local keys = {}
  for _, per_unit in pairs(labels) do
    for k in pairs(per_unit) do
      keys[k] = true
    end
  end
  print(("labels cover %d units, extraction found %d"):format(vim.tbl_count(keys), total))
  if vim.tbl_count(keys) ~= total then
    os.exit(1)
  end
end
