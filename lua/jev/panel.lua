-- A small float, top right, that shows the run happening: progress, cost, latency, and
-- the last three hits. Non-focusable, closes itself after the last batch.
local M = {}

M.width = 46
M.win, M.buf, M.timer = nil, nil, nil

local function bar(done, total)
  local slots = 12
  local filled = total > 0 and math.floor(slots * done / total + 0.5) or 0
  return ("█"):rep(filled) .. ("░"):rep(slots - filled)
end

local function money(usd)
  return usd < 0.01 and ("$%.4f"):format(usd) or ("$%.2f"):format(usd)
end

local function tokens(n)
  return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(n)
end

local function lines_for(info)
  local blocks = bar(info.batches_done, info.batches_total)
  local out = {
    " jev  " .. info.question:sub(1, M.width - 8),
    " " .. blocks .. ("  %d/%d batches"):format(info.batches_done, info.batches_total),
    ("  %d functions · %d requests · %d in flight"):format(info.units, info.requests, info.in_flight),
    ("  ~%s tokens · %s"):format(tokens(info.tokens), money(info.cost)),
    ("  %.1fs elapsed · p50 %dms"):format(info.elapsed_ms / 1000, info.p50),
  }
  local hl = {
    { 0, "Title" },
    { 1, "String", 1 + #blocks }, -- colour the bar, not the counter beside it
    { 2, "Comment" },
    { 3, "Comment" },
    { 4, "Comment" },
  }
  for _, hit in ipairs(info.recent) do
    out[#out + 1] = ("  %.2f %s"):format(hit.p, hit.unit.name)
    hl[#hl + 1] = { #out - 1, hit.p >= 0.9 and "JevHit" or "JevFaint" }
  end
  if info.note then
    out[#out + 1] = "  " .. info.note
    hl[#hl + 1] = { #out - 1, "WarningMsg" }
  end
  return out, hl
end

function M.open(question)
  M.close(0)
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].bufhidden = "wipe"
  M.config = {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = vim.o.columns - 2,
    width = M.width,
    height = 5,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
    zindex = 60,
  }
  M.win = vim.api.nvim_open_win(M.buf, false, M.config)
  vim.wo[M.win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder"
  M.render({
    question = question,
    units = 0, requests = 0, in_flight = 0, tokens = 0, cost = 0,
    elapsed_ms = 0, p50 = 0, batches_done = 0, batches_total = 0, recent = {},
  })
end

function M.render(info)
  if not (M.win and vim.api.nvim_win_is_valid(M.win)) then
    return
  end
  local lines, hl = lines_for(info)
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(M.buf, -1, 0, -1)
  for _, h in ipairs(hl) do
    pcall(vim.api.nvim_buf_set_extmark, M.buf, vim.api.nvim_create_namespace("jev_panel"), h[1], 0, {
      end_row = h[3] and h[1] or h[1] + 1,
      end_col = h[3],
      hl_group = h[2],
    })
  end
  M.config.height = #lines
  vim.api.nvim_win_set_config(M.win, M.config)
end

function M.close(delay_ms)
  if M.timer then
    M.timer:stop()
    M.timer = nil
  end
  local function shut()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      vim.api.nvim_win_close(M.win, true)
    end
    M.win, M.buf = nil, nil
  end
  if (delay_ms or 0) <= 0 then
    return shut()
  end
  M.timer = vim.defer_fn(shut, delay_ms)
end

return M
