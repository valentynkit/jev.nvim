local jev = require("jev")
local cache = require("jev.cache")
local H = dofile("tests/helpers.lua")

local Q = "swallows an exception without logging or rethrowing it"

local function edit(path)
  vim.cmd.edit(path)
  return vim.api.nvim_get_current_buf()
end

local function ask(question, opts)
  jev.last = nil
  jev.ask(question, vim.tbl_extend("force", { panel = false }, opts or {}))
  H.wait(function()
    return jev.last ~= nil
  end, 20000)
  return jev.last
end

local function texts()
  return vim.tbl_map(function(item)
    return item.text
  end, vim.fn.getqflist())
end

describe("the :Jev command", function()
  before_each(function()
    H.reset()
    cache.clear()
    jev.setup({})
    vim.cmd("silent! cclose")
  end)

  it("fills quickfix with one entry per function, sorted descending", function()
    edit("fixtures/corpus/errors.py")
    ask(Q)
    local list = texts()
    assert.equals(4, #list)
    local previous = 1.1
    for _, text in ipairs(list) do
      local p = tonumber(text:match("^(%d%.%d+)"))
      assert.is_truthy(p)
      assert.is_true(p <= previous, "list is not sorted: " .. table.concat(list, " | "))
      previous = p
    end
    assert.is_truthy(list[1]:match("save_event$"))
  end)

  it("marks entries under the threshold instead of dropping them", function()
    edit("fixtures/corpus/errors.py")
    ask(Q, { threshold = 0.75 })
    local below = vim.tbl_filter(function(t)
      return t:find("(below t)", 1, true) ~= nil
    end, texts())
    assert.equals(3, #below)
  end)

  it("runs through the user command, range form included", function()
    local buf = edit("fixtures/corpus/errors.py")
    jev.last = nil
    jev.setup({ panel = false })
    vim.cmd("11,17Jev " .. Q)
    H.wait(function()
      return jev.last ~= nil
    end, 20000)
    assert.equals(1, #vim.fn.getqflist())
    assert.is_truthy(texts()[1]:match("save_event$"))
    assert.equals(buf, vim.fn.getqflist()[1].bufnr)
  end)

  it("holds the entry under the cursor while later batches land", function()
    edit("fixtures/corpus/errors.py")
    H.control({ delay_ms = 120 })
    jev.last = nil
    jev.ask(Q, { panel = false, width = 1, concurrency = 1 })
    H.wait(function()
      return #vim.fn.getqflist() >= 2
    end, 20000)
    vim.cmd("cnext")
    local idx = vim.fn.getqflist({ idx = 0 }).idx
    local pinned = vim.fn.getqflist()[idx].text
    H.wait(function()
      return jev.last ~= nil
    end, 20000)
    assert.equals(4, #vim.fn.getqflist())
    assert.equals(pinned, vim.fn.getqflist()[idx].text)
  end)

  it("re-asks only the function that changed", function()
    local buf = edit("fixtures/corpus/errors.py")
    ask(Q)
    assert.equals(4, H.stats().questions)

    H.reset()
    vim.api.nvim_buf_set_lines(buf, 16, 16, false, { "    # touched by the spec" })
    ask(Q)
    assert.equals(1, H.stats().questions)
    assert.equals(4, #vim.fn.getqflist())
    vim.cmd("silent! edit!")
  end)

  it("says what is missing instead of raising", function()
    vim.cmd("enew")
    vim.bo.filetype = "cobol"
    local notes = {}
    local real = vim.notify
    vim.notify = function(msg)
      notes[#notes + 1] = msg
    end
    local ok = pcall(jev.ask, Q, { panel = false })
    vim.notify = real
    assert.is_true(ok)
    assert.equals(1, #notes)
    assert.is_truthy(notes[1]:match("^jev: "))
    assert.is_nil(notes[1]:match("stack traceback"))
  end)
end)
