local batch = require("jev.batch")
local extract = require("jev.extract")
local H = dofile("tests/helpers.lua")

local QUESTION = "swallows an exception without logging or rethrowing it"

local function corpus_units()
  local units = {}
  for _, path in ipairs(vim.fn.glob("fixtures/corpus/*", false, true)) do
    vim.list_extend(units, (extract.from_file(path)))
  end
  return units
end

local function run(units, opts)
  local seen, result = {}, {}
  batch.run(units, vim.tbl_extend("force", { question = QUESTION, repo = "jev.nvim" }, opts or {}), {
    on_batch = function(hits)
      vim.list_extend(seen, hits)
    end,
    on_done = function(stats)
      result.stats = stats
      result.done = true
    end,
  })
  H.wait(function()
    return result.done
  end, 30000)
  result.hits = seen
  return result
end

describe("batch", function()
  before_each(function()
    H.reset()
  end)

  it("estimates tokens the way fast-jev-compaction does", function()
    -- letters: one token per six, digits a half each, other symbols nine tenths.
    assert.equals(1, batch.estimate("hello"))
    assert.equals(2, batch.estimate("abcdefg"))
    assert.equals(2, batch.estimate("1234"))
    assert.equals(2, batch.estimate("{}"))
    assert.equals(0, batch.estimate("   \n\t"))
  end)

  it("packs to the budget and to the width", function()
    local items = {}
    for i = 1, 10 do
      items[i] = { est = 1000 }
    end
    assert.equals(1, #batch.pack(items, 45000))
    assert.equals(4, #batch.pack(items, 3400))
    assert.equals(4, #batch.pack(items, 45000, 3))
    -- One item over budget still ships, alone, rather than being dropped.
    assert.equals(1, #batch.pack({ { est = 99999 } }, 1000))
  end)

  it("lands within 20% of the tokens the fake reports", function()
    H.control({ count_tokens = true })
    local r = run(corpus_units())
    assert.equals(1, r.stats.batches_done)
    local reported = r.stats.input_tokens
    local estimated = r.stats.est_tokens
    assert.is_true(reported > 0)
    local error_pct = math.abs(estimated - reported) / reported
    assert.is_true(
      error_pct < 0.20,
      ("estimate %d vs reported %d, off by %.1f%%"):format(estimated, reported, error_pct * 100)
    )
  end)

  it("judges every unit in the corpus", function()
    local units = corpus_units()
    local r = run(units, { width = 7 })
    assert.equals(#units, #r.hits)
    assert.equals(0, r.stats.failed)
    assert.equals(7, r.stats.batches_total)
  end)

  it("bisects once when a batch comes back too big", function()
    local units = vim.list_slice(corpus_units(), 1, 8)
    H.control({ max_questions = 4 })
    local r = run(units)
    assert.equals(1, r.stats.splits)
    assert.equals(8, #r.hits)
    assert.equals(0, r.stats.failed)
  end)

  it("halves a single oversize unit once, then gives up without hanging", function()
    local big = table.concat({
      "def enormous(value):",
      string.rep("    value = value + 1\n", 12000),
    }, "\n")
    local units = extract.from_string(big, "python", "huge.py")
    assert.equals(1, #units)
    -- Nothing this unit can shrink to will fit, so the run must terminate anyway.
    H.control({ max_body = 200 })
    local r = run(units)
    assert.equals(1, r.stats.failed)
    assert.equals(0, #r.hits)
    assert.is_true(r.stats.splits >= 2)
  end)

  it("counts a dead request instead of raising", function()
    H.control({ fail_times = 99, fail_status = 500 })
    local r = run(vim.list_slice(corpus_units(), 1, 2), { client = { backoff_ms = { 10, 10 } } })
    assert.equals(2, r.stats.failed)
    assert.equals(1, #r.stats.errors)
    assert.equals(0, #r.hits)
  end)

  it("keeps at most `concurrency` requests in flight", function()
    H.control({ delay_ms = 60 })
    local peak = 0
    local units = corpus_units()
    local result = {}
    batch.run(units, { question = QUESTION, width = 4, concurrency = 3 }, {
      on_batch = function(_, stats)
        peak = math.max(peak, stats.in_flight)
      end,
      on_done = function()
        result.done = true
      end,
    })
    H.wait(function()
      return result.done
    end, 30000)
    assert.is_true(peak <= 3, "peak in flight was " .. peak)
  end)

  it("medians in code, never in Jev", function()
    assert.equals(0, batch.p50({}))
    assert.equals(3, batch.p50({ 5, 1, 3 }))
    assert.equals(2, batch.p50({ 4, 1, 3, 2 })) -- nearest rank, not an interpolated median
  end)
end)
