local jev = require("jev")
local cache = require("jev.cache")
local H = dofile("tests/helpers.lua")

local Q = "swallows an exception without logging or rethrowing it"

local function ask(question, opts)
  jev.last = nil
  jev.ask(question, vim.tbl_extend("force", { panel = false }, opts or {}))
  H.wait(function()
    return jev.last ~= nil
  end, 20000)
  return jev.last
end

describe("globs, filters and the cost gate", function()
  before_each(function()
    H.reset()
    cache.clear()
    jev.setup({})
    vim.cmd("enew!")
  end)

  it("judges only the files the glob matches", function()
    ask(Q, { glob = "fixtures/corpus/*.lua" })
    assert.equals(8, #vim.fn.getqflist())
    for _, item in ipairs(vim.fn.getqflist()) do
      assert.is_truthy(vim.fn.bufname(item.bufnr):match("%.lua$"))
    end
  end)

  it("takes the glob off the end of the command line", function()
    jev.last = nil
    vim.cmd("Jev " .. Q .. " fixtures/corpus/*.rs")
    H.wait(function()
      return jev.last ~= nil
    end, 20000)
    assert.equals(8, #vim.fn.getqflist())
  end)

  it("runs pre_filter before Jev sees anything", function()
    ask(Q, { glob = "fixtures/corpus/errors.py", pre_filter = "except" })
    assert.equals(2, H.stats().questions)
    assert.equals(2, #vim.fn.getqflist())

    H.reset()
    cache.clear()
    ask(Q, { glob = "fixtures/corpus/errors.py" })
    assert.equals(4, H.stats().questions)
  end)

  it("takes a predicate as well as a pattern", function()
    ask(Q, {
      glob = "fixtures/corpus/errors.py",
      pre_filter = function(unit)
        return unit.name == "save_event"
      end,
    })
    assert.equals(1, H.stats().questions)
  end)

  it("asks before reading the files, not only before sending them", function()
    local prompts = {}
    local real = vim.fn.confirm
    vim.fn.confirm = function(text)
      prompts[#prompts + 1] = text
      return 2 -- No
    end
    jev.last = nil
    jev.ask(Q, { panel = false, glob = "fixtures/corpus/*", confirm_above = 1 })
    vim.fn.confirm = real
    -- The scan is synchronous, so the question about reading comes first and alone.
    assert.equals(1, #prompts)
    assert.is_truthy(prompts[1]:match("files to read and parse"))
    assert.equals(0, H.stats().questions)
  end)

  it("says so when a glob matches only directories", function()
    local notes = {}
    local real = vim.notify
    vim.notify = function(msg)
      notes[#notes + 1] = msg
    end
    jev.ask(Q, { panel = false, glob = "fixtures/corpus" })
    vim.notify = real
    assert.equals(1, #notes)
    assert.is_truthy(notes[1]:match("matched only directories"))
  end)

  it("asks before a wide glob, and sends nothing on no", function()
    local asked = 0
    local real = vim.fn.confirm
    vim.fn.confirm = function()
      asked = asked + 1
      return 2 -- No
    end
    jev.last = nil
    jev.ask(Q, { panel = false, glob = "fixtures/corpus/*", confirm_above = 1 })
    vim.fn.confirm = real
    assert.equals(1, asked)
    assert.is_nil(jev.last)
    assert.equals(0, H.stats().questions)
  end)

  it("skips the gate for :Jev!", function()
    local asked = 0
    local real = vim.fn.confirm
    vim.fn.confirm = function()
      asked = asked + 1
      return 2
    end
    jev.setup({ confirm_above = 1, panel = false })
    jev.last = nil
    vim.cmd("Jev! " .. Q .. " fixtures/corpus/errors.py")
    H.wait(function()
      return jev.last ~= nil
    end, 20000)
    vim.fn.confirm = real
    assert.equals(0, asked)
    assert.equals(4, H.stats().questions)
  end)

  it("says so when a glob matches nothing", function()
    local notes = {}
    local real = vim.notify
    vim.notify = function(msg)
      notes[#notes + 1] = msg
    end
    jev.ask(Q, { panel = false, glob = "fixtures/corpus/*.cobol" })
    vim.notify = real
    assert.equals(1, #notes)
    assert.is_truthy(notes[1]:match("nothing matched"))
  end)
end)
