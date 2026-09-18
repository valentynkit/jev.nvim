local jev = require("jev")
local cache = require("jev.cache")
local marks = require("jev.marks")
local panel = require("jev.panel")
local H = dofile("tests/helpers.lua")

local Q = "swallows an exception without logging or rethrowing it"

local function panel_lines()
  if not (panel.win and vim.api.nvim_win_is_valid(panel.win)) then
    return nil
  end
  return vim.api.nvim_buf_get_lines(panel.buf, 0, -1, false)
end

describe("the panel and the virtual text", function()
  before_each(function()
    H.reset()
    cache.clear()
    jev.setup({})
    panel.close(0)
    marks.clear()
  end)

  it("shows the question, the bar and the last hits while the run happens", function()
    vim.cmd.edit("fixtures/corpus/errors.py")
    H.control({ delay_ms = 80 })
    jev.last = nil
    jev.ask(Q, { width = 1, concurrency = 1, panel_linger_ms = 100000 })

    H.wait(function()
      local lines = panel_lines()
      return lines ~= nil and lines[1]:find(Q:sub(1, 20), 1, true) ~= nil
    end)
    local mid = panel_lines()
    assert.is_truthy(mid[2]:match("█") or mid[2]:match("░"))
    assert.is_truthy(mid[2]:match("%d+/%d+ batches"))
    assert.is_truthy(mid[3]:match("%d+ functions · %d+ requests · %d+ in flight"))
    assert.is_truthy(mid[4]:match("tokens · %$"))
    assert.is_truthy(mid[5]:match("s elapsed · p50 %d+ms"))

    H.wait(function()
      return jev.last ~= nil
    end, 20000)
    local final = panel_lines()
    assert.is_truthy(final[2]:match("4/4 batches"))
    -- The tail is the three most recent hits, newest first, so the last unit is on top.
    assert.is_truthy(final[6]:match("^%s+0%.%d%d connect_pool$"), final[6])
    assert.equals(8, #final)
    panel.close(0)
  end)

  it("closes itself after the last batch", function()
    vim.cmd.edit("fixtures/corpus/errors.py")
    jev.last = nil
    jev.ask(Q, { panel_linger_ms = 150 })
    H.wait(function()
      return jev.last ~= nil
    end, 20000)
    assert.is_truthy(panel_lines())
    H.wait(function()
      return panel_lines() == nil
    end, 5000)
  end)

  it("stays shut when panel is off", function()
    vim.cmd.edit("fixtures/corpus/errors.py")
    jev.last = nil
    jev.ask(Q, { panel = false })
    H.wait(function()
      return jev.last ~= nil
    end, 20000)
    assert.is_nil(panel_lines())
  end)

  it("puts the probability on the signature line of every hit", function()
    local buf = vim.fn.bufadd("fixtures/corpus/errors.py")
    vim.fn.bufload(buf)
    vim.cmd.edit("fixtures/corpus/errors.py")
    jev.last = nil
    jev.ask(Q, { panel = false, threshold = 0.75 })
    H.wait(function()
      return jev.last ~= nil
    end, 20000)

    local found = marks.list(vim.api.nvim_get_current_buf())
    assert.equals(1, #found) -- only save_event clears 0.75 on this file
    local mark = found[1]
    assert.equals(10, mark[2]) -- 0-based row of `def save_event(conn, event):`
    assert.equals("  0.94 jev", mark[4].virt_text[1][1])
    assert.equals("JevHit", mark[4].virt_text[1][2])
  end)

  it("clears the marks on :JevClear and on the next run", function()
    vim.cmd.edit("fixtures/corpus/errors.py")
    jev.last = nil
    jev.ask(Q, { panel = false })
    H.wait(function()
      return jev.last ~= nil
    end, 20000)
    assert.equals(1, #marks.list(vim.api.nvim_get_current_buf()))
    vim.cmd("JevClear")
    assert.equals(0, #marks.list(vim.api.nvim_get_current_buf()))
  end)

  it("leaves the buffer alone when virtual_text is off", function()
    vim.cmd.edit("fixtures/corpus/errors.py")
    jev.last = nil
    jev.ask(Q, { panel = false, virtual_text = false })
    H.wait(function()
      return jev.last ~= nil
    end, 20000)
    assert.equals(0, #marks.list(vim.api.nvim_get_current_buf()))
  end)
end)
