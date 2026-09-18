local client = require("jev.client")
local H = dofile("tests/helpers.lua")

local function body(n)
  local questions = {}
  for i = 1, n or 1 do
    questions["q" .. i] = {
      type = "noul",
      instructions = {
        question = 'Does this function implement, or is it directly responsible for: "swallows an exception without logging or rethrowing it"?',
        unit = { file = "fixtures/corpus/errors.py", name = "save_event" },
      },
    }
  end
  return { model = "jev-1.13.0", state = { repo = "jev.nvim" }, questions = questions }
end

local function ask(payload, opts)
  local result = {}
  client.ask(payload, opts, function(err, data, meta)
    result.err, result.data, result.meta = err, data, meta
    result.done = true
  end)
  H.wait(function()
    return result.done
  end)
  return result
end

describe("client", function()
  before_each(function()
    H.reset()
  end)

  it("reads the base URL from JEV_BASE_URL", function()
    assert.equals(H.base .. "/v1/systemone", client.endpoint())
  end)

  it("gets a noul back from the fake", function()
    local r = ask(body(1))
    assert.is_nil(r.err)
    assert.equals(0.94, r.data.answers.q1.noul)
    assert.equals(1, r.meta.attempts)
  end)

  it("retries once on 429 and honours retry-after", function()
    H.control({ fail_times = 1, fail_status = 429, retry_after = "0.2" })
    local started = vim.uv.now()
    local r = ask(body(1))
    assert.is_nil(r.err)
    assert.equals(2, r.meta.attempts)
    assert.equals(1, H.stats().failures)
    assert.is_true(vim.uv.now() - started >= 200)
  end)

  it("retries a 500 twice, then gives up with one message", function()
    H.control({ fail_times = 9, fail_status = 503 })
    local r = ask(body(1), { backoff_ms = { 10, 10 } })
    assert.equals(3, r.meta.attempts)
    assert.is_truthy(r.err.message:match("^jev HTTP 503"))
    assert.is_nil(r.err.message:match("stack traceback"))
  end)

  it("never retries a 4xx that is not 429", function()
    H.control({ fail_times = 9, fail_status = 422 })
    local r = ask(body(1), { backoff_ms = { 10, 10 } })
    assert.equals(1, r.meta.attempts)
    assert.equals(422, r.err.status)
  end)

  it("flags an over-budget batch instead of failing it", function()
    H.control({ max_questions = 1 })
    local r = ask(body(2))
    assert.is_true(r.err.too_big)
    assert.equals(400, r.err.status)
  end)

  it("gives up when the shared deadline passes, whatever the attempt count", function()
    H.control({ fail_times = 9, fail_status = 500 })
    local r = ask(body(1), { timeout_ms = 120, backoff_ms = { 300, 300 } })
    assert.is_truthy(r.err.message)
    assert.is_true(r.meta.latency_ms < 2000)
  end)

  it("names the missing binary rather than raising", function()
    local path = vim.env.PATH
    vim.env.PATH = "/nonexistent"
    local msg = client.preflight()
    vim.env.PATH = path
    assert.is_truthy(msg:match("curl is not on PATH"))
  end)

  it("names the missing key when no base URL is set", function()
    local base, key = vim.env.JEV_BASE_URL, vim.env.TYPESAFE_API_KEY
    vim.env.JEV_BASE_URL, vim.env.TYPESAFE_API_KEY = nil, nil
    local msg = client.preflight()
    vim.env.JEV_BASE_URL, vim.env.TYPESAFE_API_KEY = base, key
    assert.is_truthy(msg:match("TYPESAFE_API_KEY"))
  end)
end)
