-- :Jev, and the wiring between extraction, batching, quickfix, the panel and the marks.
local batch = require("jev.batch")
local cache = require("jev.cache")
local client = require("jev.client")
local extract = require("jev.extract")
local marks = require("jev.marks")
local panel = require("jev.panel")
local qf = require("jev.qf")

local M = {}

--- Stats from the last finished run. nil while one is in flight.
M.last = nil

M.opts = {
  threshold = 0.75, -- from the sweep in scripts/measure.lua
  confirm_above = 200, -- units, above which a glob asks first
  concurrency = 4,
  budget = 45000,
  width = nil, -- questions per request; nil means budget only
  panel = true,
  panel_linger_ms = 2000,
  virtual_text = true,
  pre_filter = nil, -- lua pattern or fun(unit): boolean, run before Jev sees anything
  repo = nil,
}

function M.setup(opts)
  M.opts = vim.tbl_extend("force", M.opts, opts or {})
  marks.setup_highlights()
  return M.opts
end

local function fail(msg)
  vim.notify("jev: " .. msg, vim.log.levels.WARN)
end

-- Shared state: what the repo is, once per request, never per question.
local function repo_card(units)
  if M.opts.repo then
    return M.opts.repo
  end
  local langs = {}
  for _, u in ipairs(units) do
    langs[u.lang] = true
  end
  local names = vim.tbl_keys(langs)
  table.sort(names)
  return ("%s (%s)"):format(vim.fn.fnamemodify(vim.uv.cwd(), ":t"), table.concat(names, ", "))
end

local function keep(unit, pre_filter)
  if not pre_filter then
    return true
  end
  if type(pre_filter) == "function" then
    return pre_filter(unit) and true or false
  end
  return (unit.source:find(pre_filter) or unit.signature:find(pre_filter)) ~= nil
end

--- Units for one invocation: the buffer, or every file a glob resolves to.
function M.collect(glob)
  if not glob then
    local units, err = extract.from_buf(0)
    return units, err
  end
  local units, misses = {}, {}
  for _, path in ipairs(vim.fn.glob(glob, false, true)) do
    if vim.fn.isdirectory(path) == 0 then
      local found, err = extract.from_file(path)
      if err then
        misses[#misses + 1] = err
      end
      vim.list_extend(units, found)
    end
  end
  return units, #units == 0 and (misses[1] or ("nothing matched " .. glob)) or nil
end

local function confirm(plan, opts)
  local line = ("jev: %d functions, %d requests, about $%.4f"):format(plan.units, plan.requests, plan.cost)
  if opts.bang or plan.units <= opts.confirm_above then
    vim.notify(line)
    return true
  end
  return vim.fn.confirm(line .. ". Send?", "&Yes\n&No", 2) == 1
end

--- The whole run. Never blocks the UI; every callback is already on the main loop.
function M.ask(question, opts)
  opts = vim.tbl_extend("force", M.opts, opts or {})
  -- One run at a time. Two overlapping runs share the quickfix list, the marks and the
  -- panel, so the second one's :JevSort would rank two different questions together.
  if M.busy then
    return fail("a run is already in flight; wait for it or :JevClear")
  end
  local why = client.preflight()
  if why then
    return fail(why)
  end

  local units, err = M.collect(opts.glob)
  if opts.range then
    units = vim.tbl_filter(function(u)
      return u.lnum <= opts.range[2] and u.end_lnum >= opts.range[1]
    end, units)
  end
  units = vim.tbl_filter(function(u)
    return keep(u, opts.pre_filter)
  end, units)
  if #units == 0 then
    return fail(err or "no functions here to judge")
  end

  M.last = nil
  local known, unknown = cache.split(question, units)
  local plan = batch.plan(unknown, question, opts)
  if not confirm(plan, opts) then
    return
  end

  M.busy = true
  marks.clear()
  qf.start(question)
  qf.open()
  local recent = {}
  local function show(hits)
    qf.append(hits, opts.threshold)
    for _, hit in ipairs(hits) do
      cache.set(question, hit.unit, hit.p)
      if opts.virtual_text then
        marks.place(hit, opts.threshold)
      end
      table.insert(recent, 1, hit)
    end
    recent = vim.list_slice(recent, 1, 3)
  end

  if opts.panel then
    panel.open(question)
  end
  local function paint(stats, note)
    if not opts.panel then
      return
    end
    panel.render({
      question = question,
      units = #units,
      requests = stats.requests,
      in_flight = stats.in_flight,
      tokens = stats.est_tokens,
      cost = stats.est_tokens * batch.usd_per_input_token,
      elapsed_ms = vim.uv.now() - stats.started,
      p50 = batch.p50(stats.latencies),
      batches_done = stats.batches_done,
      batches_total = stats.batches_total,
      recent = recent,
      note = note,
    })
  end

  show(known)
  batch.run(unknown, {
    question = question,
    repo = repo_card(units),
    budget = opts.budget,
    width = opts.width,
    concurrency = opts.concurrency,
  }, {
    on_batch = function(hits, stats)
      show(hits)
      paint(stats)
    end,
    on_error = function(message, stats)
      fail(message)
      paint(stats, "one batch failed, list is partial")
    end,
    on_done = function(stats)
      M.busy = false
      if qf.untouched() then
        qf.sort(opts.threshold)
      elseif #qf.entries > 1 then
        vim.notify("jev: done. :JevSort to rank the list by probability")
      end
      paint(stats)
      panel.close(opts.panel_linger_ms)
      M.last = stats
      if opts.on_done then
        opts.on_done(stats)
      end
    end,
  })
end

-- ponytail: the glob is the last whitespace-separated word when it looks like a path.
-- Ceiling: a question whose last word ends in a dot-extension would be mistaken for a
-- glob, so `--` ends the question explicitly and everything after it is the glob, spaces
-- included. `:Jev is the ratio a.b safe --` asks about a.b instead of globbing for it.
local function split_args(args)
  local question, rest = args:match("^(.-)%s+%-%-%s*(.*)$")
  if question then
    return vim.trim(question), rest ~= "" and rest or nil
  end
  local last = args:match("(%S+)$")
  if last and (last:find("[*/]") or last:match("%.%w+$")) and args:find("%s") then
    return vim.trim(args:sub(1, #args - #last)), last
  end
  return vim.trim(args), nil
end

function M.command(a)
  local question, glob = split_args(a.args)
  if question == "" then
    return fail("give it a question, for example :Jev functions that swallow errors")
  end
  -- A range is line numbers in this buffer; a glob is other files. Applying one to the
  -- other keeps whichever functions happen to overlap those lines, which is nonsense.
  if glob and a.range == 2 then
    return fail("a range and a glob do not mix, pick one")
  end
  M.ask(question, {
    glob = glob,
    bang = a.bang,
    range = a.range == 2 and { a.line1, a.line2 } or nil,
  })
end

function M.sort()
  qf.sort(M.opts.threshold)
end

function M.clear()
  marks.clear()
  panel.close(0)
  M.busy = false
end

return M
