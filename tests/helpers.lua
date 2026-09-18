-- Shared by the specs: talk to the fake's control endpoints, and wait for async work.
local H = {}

H.base = os.getenv("JEV_BASE_URL") or "http://127.0.0.1:4372"

local function call(path, body)
  local args = { "curl", "-sS", H.base .. path }
  if body then
    vim.list_extend(args, { "-X", "POST", "--data-binary", vim.json.encode(body) })
  end
  local res = vim.system(args, { text = true }):wait()
  local ok, decoded = pcall(vim.json.decode, res.stdout or "")
  return ok and decoded or { error = res.stdout, stderr = res.stderr }
end

function H.control(opts)
  return call("/_control", opts or {})
end

function H.reset()
  H.control({
    fail_times = 0,
    fail_status = 429,
    retry_after = "",
    max_questions = 0,
    max_body = 0,
    delay_ms = 0,
    count_tokens = false,
    default_noul = 0.02,
  })
  return call("/_reset")
end

function H.stats()
  return call("/_stats")
end

--- Block until `fn` returns true. Fails the spec on timeout.
function H.wait(fn, ms)
  local ok = vim.wait(ms or 8000, fn, 20)
  assert(ok, "timed out waiting for async work")
end

return H
