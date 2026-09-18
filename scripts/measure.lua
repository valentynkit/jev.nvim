-- The headline number, and the sweep behind it.
--   nvim --headless -u tests/minimal.lua -l scripts/measure.lua
-- Reads JEV_BASE_URL (the replay proxy by default, via `make measure`), prints one line,
-- writes measure.json next to it, and exits 1 if held-out precision has regressed.
local batch = require("jev.batch")
local extract = require("jev.extract")
local score = require("jev.score")

local fixtures = os.getenv("JEV_FIXTURES") or "fixtures"
local write_baseline = vim.tbl_contains(_G.arg or {}, "--write-baseline")
local TARGET_PRECISION = 0.90
-- Budget packing, same as :Jev. Keeping it at one request per question means a
-- rate-limited recording loses at most one question's work before it can resume.
local WIDTH = tonumber(os.getenv("JEV_WIDTH") or "") or nil
local SLACK = 0.02 -- how far held-out precision may drift before this exits 1

-- print() goes to stderr under --headless, and this line is meant to be piped.
local function say(line)
  io.stdout:write(line .. "\n")
end

local function read_json(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

local function die(msg)
  io.stderr:write("measure: " .. msg .. "\n")
  os.exit(1)
end

local labels = read_json(fixtures .. "/labels.json") or die("no " .. fixtures .. "/labels.json")

local files, units = {}, {}
for _, path in ipairs(vim.fn.glob(fixtures .. "/corpus/*", false, true)) do
  if vim.fn.isdirectory(path) == 0 then
    files[#files + 1] = vim.fn.fnamemodify(path, ":t")
    vim.list_extend(units, (extract.from_file(path)))
  end
end
table.sort(files)
local tune_files, hold_files = score.split(files)
local in_tune = {}
for _, f in ipairs(tune_files) do
  in_tune[f] = true
end

local questions = vim.tbl_keys(labels)
table.sort(questions)

local rows = { tune = {}, hold = {} }
local totals = { requests = 0, latencies = {}, tokens = 0, reported_tokens = 0, failed = 0 }
local recorded = false

for _, question in ipairs(questions) do
  local finished, answers = false, {}
  batch.run(units, { question = question, repo = "jev.nvim corpus", width = WIDTH }, {
    on_batch = function(hits)
      for _, hit in ipairs(hits) do
        answers[vim.fn.fnamemodify(hit.unit.file, ":t") .. ":" .. hit.unit.name] = hit.p
      end
    end,
    on_error = function(message)
      if message:find("no recording", 1, true) then
        die("no recorded answers yet. Run `make record` once against a real endpoint.")
      end
      die(message)
    end,
    on_done = function(stats)
      totals.requests = totals.requests + stats.requests
      totals.failed = totals.failed + stats.failed
      totals.tokens = totals.tokens + stats.est_tokens
      totals.reported_tokens = totals.reported_tokens + stats.input_tokens
      vim.list_extend(totals.latencies, stats.latencies)
      recorded = recorded or stats.recorded_latency == true
      finished = true
    end,
  })
  if not vim.wait(300000, function()
    return finished
  end, 50) then
    die("timed out asking: " .. question)
  end

  for key, label in pairs(labels[question]) do
    local p = answers[key]
    if p == nil then
      die("no answer for " .. key .. " on: " .. question)
    end
    local file = key:match("^([^:]+)")
    local bucket = in_tune[file] and rows.tune or rows.hold
    bucket[#bucket + 1] = { p = p, label = label, key = key, question = question }
  end
end

local tune_sweep = score.sweep(rows.tune)
local threshold = score.choose(tune_sweep, TARGET_PRECISION)
local hold_sweep = score.sweep(rows.hold)
local hold = score.at(rows.hold, threshold)
local lo, hi = score.wilson(hold.true_hits, hold.hits)

local source = recorded and "recorded" or "fake"
local tokens = totals.reported_tokens > 0 and totals.reported_tokens or totals.tokens
local per_query_tokens = tokens / #questions
local report = {
  source = source,
  model = batch.model,
  questions = #questions,
  units = #units,
  requests = totals.requests,
  functions_per_request = #units * #questions / totals.requests,
  usd_per_query = per_query_tokens * batch.usd_per_input_token,
  p50_ms = batch.p50(totals.latencies),
  threshold = threshold,
  tune = { n = #rows.tune, sweep = tune_sweep },
  hold = {
    n = #rows.hold,
    hits = hold.hits,
    true_hits = hold.true_hits,
    precision = hold.precision,
    recall = hold.recall,
    ci = { lo, hi },
    sweep = hold_sweep,
  },
}

local headline = ("%.0f functions per request ($%.4f/query, %d ms p50, precision %.2f at t=%.2f, n=%d held out, 95%% CI %.2f-%.2f) (%d questions, threshold tuned on a disjoint %d, %s fixtures)"):format(
  report.functions_per_request,
  report.usd_per_query,
  report.p50_ms,
  hold.precision,
  threshold,
  hold.hits,
  lo,
  hi,
  #questions,
  #rows.tune,
  source
)
say(headline)
report.headline = headline

local function table_lines(title, sweep)
  say("")
  say(title)
  say("  t     hits  precision  recall")
  for _, row in ipairs(sweep) do
    say(("  %.2f  %4d  %9.3f  %6.3f"):format(row.t, row.hits, row.precision, row.recall))
  end
end
table_lines(("tuning half (n=%d judgments, %s)"):format(#rows.tune, table.concat(tune_files, " ")), tune_sweep)
table_lines(("held out (n=%d judgments, %s)"):format(#rows.hold, table.concat(hold_files, " ")), hold_sweep)

vim.fn.writefile(vim.split(vim.json.encode(report), "\n"), fixtures .. "/../measure.json")

local baseline_path = fixtures .. "/baseline.json"
local baseline = read_json(baseline_path) or {}
if write_baseline or not baseline[source] then
  baseline[source] = { precision = hold.precision, hits = hold.hits, threshold = threshold }
  vim.fn.writefile({ vim.json.encode(baseline) }, baseline_path)
  say(("\nbaseline for %s fixtures written: precision %.3f at t=%.2f"):format(source, hold.precision, threshold))
  os.exit(0)
end

if hold.precision < baseline[source].precision - SLACK then
  io.stderr:write(("measure: held-out precision fell from %.3f to %.3f\n"):format(baseline[source].precision, hold.precision))
  os.exit(1)
end
say(("\nheld-out precision %.3f, baseline %.3f, within slack %.2f"):format(hold.precision, baseline[source].precision, SLACK))
os.exit(0)
