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

-- Preferred width, clamped to whatever the editor actually is. A 40 column Zellij pane
-- would otherwise put the float's left edge off screen (anchor NE, col = columns - 2).
local function geometry()
  local width = math.max(20, math.min(M.width, vim.o.columns - 4))
  return width, math.max(width, vim.o.columns - 2)
end

local function lines_for(info, width)
  local blocks = bar(info.batches_done, info.batches_total)
  local out = {
    " jev  " .. info.question:sub(1, width - 8),
    " " .. blocks .. ("  %d/%d batches"):format(info.batches_done, info.batches_total),
  }
  local hl = {
    { 0, "Title" },
    { 1, "String", 1 + #blocks }, -- colour the bar, not the counter beside it
  }
  local function add(text, group)
    out[#out + 1] = text
    hl[#hl + 1] = { #out - 1, group }
  end
  -- In flight the three counters move independently and each wants its own line. Once
  -- nothing is moving they collapse into the one line worth reading afterwards.
  if info.done then
    add(("  done · %d functions · %d requests"):format(info.units, info.requests), "JevHit")
    add(("  %s · p50 %dms"):format(money(info.cost), info.p50), "JevHit")
  else
    add(("  %d functions · %d requests · %d in flight"):format(info.units, info.requests, info.in_flight), "Comment")
    add(("  ~%s tokens · %s"):format(tokens(info.tokens), money(info.cost)), "Comment")
    add(("  %.1fs elapsed · p50 %dms"):format(info.elapsed_ms / 1000, info.p50), "Comment")
  end
  for _, hit in ipairs(info.recent) do
    add(("  %.2f %s"):format(hit.p, hit.unit.name), hit.p >= 0.9 and "JevHit" or "JevFaint")
  end
  if info.note then
    add("  " .. info.note, "WarningMsg")
  end
  return out, hl
end

function M.open(question)
  M.close(0)
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].bufhidden = "wipe"
  local width, col = geometry()
  M.config = {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = col,
    width = width,
    height = 5,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
    zindex = 60,
  }
  M.win = vim.api.nvim_open_win(M.buf, false, M.config)
  -- Only nvim_open_win takes noautocmd; on 0.10 nvim_win_set_config raises on it.
  M.config.noautocmd = nil
  vim.wo[M.win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder"
  -- A wrapped line would push the hits below the float's height and out of sight, so a
  -- long line is truncated instead.
  vim.wo[M.win].wrap = false
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
  -- Re-read the geometry every frame; that is the whole VimResized handling.
  M.config.width, M.config.col = geometry()
  local lines, hl = lines_for(info, M.config.width)
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(M.buf, -1, 0, -1)
  for _, h in ipairs(hl) do
    pcall(vim.api.nvim_buf_set_extmark, M.buf, vim.api.nvim_create_namespace("jev_panel"), h[1], 0, {
      end_row = h[3] and h[1] or h[1] + 1,
      end_col = h[3],
      hl_group = h[2],
    })
  end
  M.config.height = math.max(1, math.min(#lines, vim.o.lines - 3))
  -- A float that will not resize is a cosmetic problem; it must never take the run down.
  pcall(vim.api.nvim_win_set_config, M.win, M.config)
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
