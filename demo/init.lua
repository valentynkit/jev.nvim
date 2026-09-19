-- Nvim config for the screencast only; `make test` never loads it.
--
-- tests/minimal.lua does the real work (isolated XDG, plenary, treesitter, the plugin).
-- This adds a colorscheme and strips the chrome the camera does not need. Nothing here
-- changes how jev.nvim behaves, so the clip shows what a lazy.nvim install gives you.
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h")
dofile(root .. "/tests/minimal.lua")

-- Kanagawa Wave, cloned like the test deps so the demo renders from a clean clone.
local theme = root .. "/.tests/site/kanagawa.nvim"
if vim.fn.isdirectory(theme) == 0 then
  vim.fn.system({ "git", "clone", "-q", "--depth", "1", "https://github.com/rebelot/kanagawa.nvim", theme })
end
vim.opt.runtimepath:prepend(theme)
vim.o.termguicolors = true
vim.cmd.colorscheme("kanagawa-wave")

-- Camera framing. Fewer columns of chrome means a bigger font at the same width, which
-- is the whole difference between readable and not on a phone.
vim.o.number = false
vim.o.signcolumn = "no"
vim.o.laststatus = 0
vim.o.ruler = false
vim.o.showmode = false
vim.o.scrolloff = 4
vim.o.wrap = false -- a wrapped line shifts everything below it mid-take
vim.opt.fillchars = { eob = " " }
