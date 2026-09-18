if vim.g.loaded_jev then
  return
end
vim.g.loaded_jev = true

require("jev.marks").setup_highlights()

vim.api.nvim_create_user_command("Jev", function(a)
  require("jev").command(a)
end, {
  nargs = "*",
  bang = true,
  range = -1,
  desc = "Ask the buffer a question, get a quickfix list",
})

vim.api.nvim_create_user_command("JevSort", function()
  require("jev").sort()
end, { desc = "Sort the jev quickfix list by probability" })

vim.api.nvim_create_user_command("JevClear", function()
  require("jev").clear()
end, { desc = "Clear jev virtual text and close the panel" })
