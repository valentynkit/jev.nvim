-- Minimal init for tests, scripts and the demo tape. Clones plenary and
-- nvim-treesitter into .tests/ and compiles the parsers the corpus needs.
-- The user's own config never loads: every XDG path points inside .tests/.
-- nvim-treesitter master, not main: main shells out to the `tree-sitter` CLI,
-- master compiles with cc, so the bootstrap needs nothing but a compiler.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local deps = root .. "/.tests/site"
local parsers = root .. "/.tests/parsers"

for _, v in ipairs({ "CONFIG", "DATA", "STATE", "CACHE" }) do
  vim.env["XDG_" .. v .. "_HOME"] = root .. "/.tests/xdg/" .. v:lower()
end

local function clone(name, url, branch)
  local dir = deps .. "/" .. name
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(deps, "p")
    local cmd = { "git", "clone", "-q", "--depth", "1" }
    if branch then
      vim.list_extend(cmd, { "--branch", branch })
    end
    vim.list_extend(cmd, { url, dir })
    vim.fn.system(cmd)
  end
  vim.opt.runtimepath:prepend(dir)
end

clone("plenary.nvim", "https://github.com/nvim-lua/plenary.nvim")
clone("nvim-treesitter", "https://github.com/nvim-treesitter/nvim-treesitter", "master")
vim.fn.mkdir(parsers, "p")
vim.opt.runtimepath:prepend(parsers)
vim.opt.runtimepath:prepend(root)

vim.o.swapfile = false
vim.o.shadafile = "NONE"

-- plenary's runner starts the child with --noplugin, so :Jev would not exist.
vim.cmd("runtime plugin/jev.lua")

require("nvim-treesitter.configs").setup({ parser_install_dir = parsers })

local want = {}
for _, lang in ipairs({ "lua", "python", "rust", "go", "javascript", "typescript", "tsx" }) do
  if vim.fn.filereadable(parsers .. "/parser/" .. lang .. ".so") == 0 then
    table.insert(want, lang)
  end
end
if #want > 0 then
  -- First run compiles each parser; a couple of minutes is normal.
  require("nvim-treesitter.install").ensure_installed_sync(want)
end
