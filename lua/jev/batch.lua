-- Token estimate, greedy packing, bounded concurrency, split-on-too-big.
-- The estimator is fast-jev-compaction src/state.ts:28-38 ported straight over (a word
-- costs a token per six letters, a digit half, any other symbol nine tenths), because a
-- flat characters-per-token ratio undercounts JSON-heavy states by up to 40%.
-- The split is every judge.py:184-198: a 400 that says max_tokens_exceeded bisects the
-- batch and requeues both halves; a single unit halves its source once, then fails.
local M = {}

M.model = os.getenv("JEV_MODEL") or "jev-1.13.0"
M.budget = 45000
M.concurrency = math.max(1, tonumber(os.getenv("JEV_CONCURRENCY") or "") or 4)
-- every units.py, for the shared state plus the envelope and the free output slot.
M.request_fixed_tokens = 262
M.output_reserve_per_question = 25
M.usd_per_input_token = 0.042 / 1000000 -- output tokens are free

M.instruction = 'Does this function implement, or is it directly responsible for: "%s"?'
M.criteria = {
  ["true"] = "the name, signature, or body directly performs what the question describes",
  ["false"] = "unrelated to the question, or shares only surface keywords with it",
}
M.note = "Each question below is independent. Judge only the unit inside it."

--- @param text string
--- @return integer estimated input tokens
function M.estimate(text)
  local tokens, i, n = 0, 1, #text
  while i <= n do
    local s, e = text:find("^[A-Za-z]+", i)
    if s then
      tokens = tokens + 1 + math.floor((e - s) / 6)
    else
      s, e = text:find("^%d+", i)
      if s then
        tokens = tokens + (e - s + 1) / 2
      else
        -- One token per codepoint, not per byte: Lua indexes bytes, so Cyrillic and CJK
        -- would otherwise cost two or three times what the TypeScript original charges.
        local b = text:byte(i)
        e = i + (b < 0xC0 and 0 or b < 0xE0 and 1 or b < 0xF0 and 2 or 3)
        if not text:sub(i, i):match("%s") then
          tokens = tokens + 0.9
        end
      end
    end
    i = e + 1
  end
  return math.ceil(tokens)
end

--- Trimmed per-unit payload: everything the question needs, nothing else.
function M.payload(unit)
  return {
    file = unit.file,
    name = unit.name,
    signature = unit.signature,
    doc = unit.doc ~= "" and unit.doc or nil,
    source = unit.source,
  }
end

--- One question entry: what actually ships per unit, instruction and criteria included.
function M.question(question, payload)
  return {
    type = "noul",
    instructions = { question = M.instruction:format(question), unit = payload },
    criteria = M.criteria,
  }
end

function M.item(unit, question)
  local payload = M.payload(unit)
  return {
    unit = unit,
    payload = payload,
    -- Estimate the whole question, not just the unit: the instruction and the two
    -- criteria ship per question and are three quarters of a short unit's cost.
    est = M.estimate(vim.json.encode(M.question(question, payload))),
  }
end

--- One request: shared state once, one noul per unit.
function M.body(question, items, repo)
  local questions = {}
  for i, it in ipairs(items) do
    questions["q" .. i] = M.question(question, it.payload)
  end
  return {
    model = M.model,
    state = { repo = repo or "", note = M.note },
    questions = questions,
  }
end

--- Greedy pack under `budget` tokens, and under `width` questions when given.
function M.pack(items, budget, width)
  local batches, current, tokens = {}, {}, M.request_fixed_tokens
  for _, it in ipairs(items) do
    local cost = it.est + M.output_reserve_per_question
    if #current > 0 and (tokens + cost > budget or (width and #current >= width)) then
      batches[#batches + 1] = current
      current, tokens = {}, M.request_fixed_tokens
    end
    current[#current + 1] = it
    tokens = tokens + cost
  end
  if #current > 0 then
    batches[#batches + 1] = current
  end
  return batches
end

--- What a run would cost, before anything is sent. Code owns the arithmetic.
function M.plan(units, question, opts)
  opts = opts or {}
  local items = vim.tbl_map(function(u)
    return M.item(u, question)
  end, units)
  local batches = M.pack(items, opts.budget or M.budget, opts.width)
  local tokens = #batches * M.request_fixed_tokens
  for _, it in ipairs(items) do
    tokens = tokens + it.est
  end
  return {
    units = #units,
    requests = #batches,
    tokens = tokens,
    cost = tokens * M.usd_per_input_token,
  }
end

--- Judge every unit. Never raises; a dead batch is counted, not thrown.
--- opts: question, repo, budget, width, concurrency, send (injectable transport)
--- cbs:  on_batch(hits, stats), on_error(message, stats), on_done(stats)
function M.run(units, opts, cbs)
  opts = opts or {}
  cbs = cbs or {}
  local send = opts.send
    or function(body, done)
      require("jev.client").ask(body, opts.client, done)
    end

  local stats = {
    units = #units,
    requests = 0,
    splits = 0,
    failed = 0,
    in_flight = 0,
    peak_in_flight = 0, -- sampled at dispatch; on_batch only ever sees the post-decrement
    batches_done = 0,
    batches_total = 0,
    est_tokens = 0,
    input_tokens = 0,
    latencies = {},
    started = vim.uv.now(),
    errors = {},
  }

  local items = vim.tbl_map(function(u)
    return M.item(u, opts.question)
  end, units)
  local queue = M.pack(items, opts.budget or M.budget, opts.width)
  stats.batches_total = #queue
  local active, done_called = 0, false

  local function finish()
    if not done_called and active == 0 and #queue == 0 then
      done_called = true
      stats.elapsed_ms = vim.uv.now() - stats.started
      if cbs.on_done then
        cbs.on_done(stats)
      end
    end
  end

  local pump

  local function too_big(batch)
    stats.splits = stats.splits + 1
    if #batch > 1 then
      local mid = math.floor(#batch / 2)
      table.insert(queue, vim.list_slice(batch, 1, mid))
      table.insert(queue, vim.list_slice(batch, mid + 1, #batch))
      stats.batches_total = stats.batches_total + 1
      return
    end
    local it = batch[1]
    if it.halved then
      stats.failed = stats.failed + 1
      stats.batches_done = stats.batches_done + 1
      return
    end
    local src = it.payload.source or ""
    it.payload = vim.tbl_extend("force", it.payload, {
      source = src:sub(1, math.max(1, math.floor(#src / 2))) .. "\n[truncated]",
    })
    it.est = M.estimate(vim.json.encode(M.question(opts.question, it.payload)))
    it.halved = true
    table.insert(queue, batch)
  end

  local function handle(batch, body, err, data, meta)
    active = active - 1
    stats.in_flight = active
    stats.requests = stats.requests + 1
    if err and err.too_big then
      too_big(batch)
    elseif err then
      stats.failed = stats.failed + #batch
      stats.batches_done = stats.batches_done + 1
      stats.errors[#stats.errors + 1] = err.message
      if cbs.on_error then
        cbs.on_error(err.message, stats)
      end
    else
      -- Latency only from requests that answered. A failed one carries its retry backoff
      -- in the same number, which would move p50 by seconds and call it Jev's time.
      -- A replayed body carries the latency the real endpoint gave, so a free replay
      -- still reports honest milliseconds instead of this machine's loopback.
      local replayed = type(data) == "table" and tonumber(data.recorded_latency_ms)
      if replayed then
        stats.recorded_latency = true
      end
      if replayed or (meta and meta.latency_ms) then
        stats.latencies[#stats.latencies + 1] = replayed or meta.latency_ms
      end
      stats.batches_done = stats.batches_done + 1
      stats.est_tokens = stats.est_tokens + M.estimate(vim.json.encode(body))
      stats.input_tokens = stats.input_tokens + ((data.usage or {}).input_tokens or 0)
      local hits = {}
      for i, it in ipairs(batch) do
        local answer = (data.answers or {})["q" .. i]
        if type(answer) == "table" and type(answer.noul) == "number" then
          hits[#hits + 1] = { unit = it.unit, p = answer.noul }
        else
          stats.failed = stats.failed + 1
        end
      end
      if cbs.on_batch then
        cbs.on_batch(hits, stats)
      end
    end
    pump()
    finish()
  end

  pump = function()
    while active < math.max(1, opts.concurrency or M.concurrency) and #queue > 0 do
      local batch = table.remove(queue, 1)
      active = active + 1
      stats.in_flight = active
      stats.peak_in_flight = math.max(stats.peak_in_flight, active)
      local body = M.body(opts.question, batch, opts.repo)
      send(body, function(err, data, meta)
        handle(batch, body, err, data, meta)
      end)
    end
  end

  if #queue == 0 then
    vim.schedule(finish)
  else
    pump()
  end
  return stats
end

--- Median of a list of numbers, or 0. Code owns arithmetic, never Jev.
function M.p50(values)
  if #values == 0 then
    return 0
  end
  local sorted = vim.deepcopy(values)
  table.sort(sorted)
  return sorted[math.ceil(#sorted / 2)]
end

return M
