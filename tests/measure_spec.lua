local score = require("jev.score")
local H = dofile("tests/helpers.lua")

local CORPUS = vim.fn.glob("fixtures/corpus/*", false, true)

local function basenames()
  return vim.tbl_map(function(p)
    return vim.fn.fnamemodify(p, ":t")
  end, CORPUS)
end

local function run_measure(fixtures_dir)
  return vim.system({
    -- progpath, not "nvim": the child must be the binary running this spec, or it pairs
    -- one version's runtime with another's.
    vim.v.progpath,
    "--headless",
    "-u",
    "tests/minimal.lua",
    "-l",
    "scripts/measure.lua",
  }, { text = true, env = { JEV_FIXTURES = fixtures_dir, JEV_BASE_URL = H.base } }):wait()
end

describe("measure", function()
  before_each(function()
    H.reset()
  end)

  it("puts no file in both halves, and every language in each", function()
    local tune, hold = score.split(basenames())
    assert.equals(6, #tune)
    assert.equals(6, #hold)
    local seen = {}
    for _, f in ipairs(tune) do
      seen[f] = true
    end
    for _, f in ipairs(hold) do
      assert.is_nil(seen[f], f .. " is in both halves")
    end
    local function exts(list)
      local out = {}
      for _, f in ipairs(list) do
        out[f:match("%.(%w+)$")] = true
      end
      return vim.tbl_count(out)
    end
    assert.equals(6, exts(tune))
    assert.equals(6, exts(hold))
  end)

  it("computes Wilson, not the normal approximation", function()
    local lo, hi = score.wilson(66, 74)
    assert.equals(0.80, tonumber(("%.2f"):format(lo)))
    assert.equals(0.94, tonumber(("%.2f"):format(hi)))
    -- The normal approximation would put the upper bound past 1.0 here.
    assert.is_true(hi < 1.0)
    local zlo, zhi = score.wilson(0, 0)
    assert.equals(0, zlo)
    assert.equals(0, zhi)
  end)

  it("picks the lowest threshold clearing the target precision", function()
    local rows = {}
    for i = 1, 5 do
      rows[i] = { p = 0.55, label = 0 }
      rows[i + 5] = { p = 0.95, label = 1 }
    end
    local sweep = score.sweep(rows, { 0.5, 0.7, 0.9 })
    assert.equals(0.5, sweep[1].t)
    assert.equals(0.5, sweep[1].precision)
    assert.equals(0.7, score.choose(sweep, 0.8))
    -- Nothing clears an impossible target, so the strictest threshold tried wins.
    assert.equals(0.9, score.choose(sweep, 1.1))
  end)

  it("prints the headline and exits 0", function()
    local res = run_measure("fixtures")
    assert.equals(0, res.code, res.stderr)
    assert.is_truthy(res.stdout:match("functions per request %(%$%d+%.%d+/query"))
    assert.is_truthy(res.stdout:match("95%% CI %d%.%d%d%-%d%.%d%d"))
    assert.is_truthy(res.stdout:match("tuning half"))
    assert.is_truthy(res.stdout:match("held out"))
  end)

  it("exits 1 when a held-out label flips against it", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    vim.fn.system({ "cp", "-R", "fixtures/.", tmp })
    local labels_path = tmp .. "/labels.json"
    local labels = vim.json.decode(table.concat(vim.fn.readfile(labels_path), "\n"))
    local q = "swallows an exception without logging or rethrowing it"
    assert.equals(1, labels[q]["report.py:drain_queue"])
    labels[q]["report.py:drain_queue"] = 0
    vim.fn.writefile({ vim.json.encode(labels) }, labels_path)

    local res = run_measure(tmp)
    assert.equals(1, res.code)
    assert.is_truthy(res.stderr:match("held%-out precision fell"))
    vim.fn.delete(tmp, "rf")
  end)
end)
