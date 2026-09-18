-- One POST to Jev over curl, async. Retry policy is jev-guard src/jev.js:29-67 ported:
-- one shared deadline across at most three attempts, backoff on 429 and 5xx only, never
-- on another 4xx. A dead request fails open; the caller degrades to its no-Jev behaviour.
local M = {}

-- Recording against a rate-limited endpoint wants more patience than an interactive
-- query does, so both are env-overridable; the defaults are what :Jev uses.
M.attempts = tonumber(os.getenv("JEV_ATTEMPTS") or "") or 3
M.timeout_ms = tonumber(os.getenv("JEV_TIMEOUT_MS") or "") or 20000
M.backoff_ms = { 500, 2000 }

function M.endpoint()
  local base = (os.getenv("JEV_BASE_URL") or "https://api.typesafe.ai"):gsub("/+$", "")
  return base .. "/v1/systemone"
end

--- Everything that must be true before the first request. Returns a message, or nil.
function M.preflight()
  if vim.fn.executable("curl") ~= 1 then
    return "curl is not on PATH, and jev.nvim speaks to Jev through it"
  end
  if not os.getenv("TYPESAFE_API_KEY") and not os.getenv("JEV_BASE_URL") then
    return "TYPESAFE_API_KEY is not set (or point JEV_BASE_URL at a local shim)"
  end
end

local function curl_args(payload_len)
  local args = {
    "curl",
    "-sS",
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
    "-H",
    "Accept: application/json",
    "-H",
    "Content-Length: " .. payload_len,
    "-w",
    "\n%{http_code} %header{retry-after}",
    "--data-binary",
    "@-",
  }
  local key = os.getenv("TYPESAFE_API_KEY")
  if key then
    table.insert(args, "-H")
    table.insert(args, "Authorization: Bearer " .. key)
  end
  return args
end

local months =
  { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6, Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }

--- retry-after is delta-seconds or an HTTP-date (RFC 7231). Milliseconds, or nil.
function M.retry_after_ms(value)
  if not value or value == "" then
    return nil
  end
  local seconds = tonumber(value)
  if seconds then
    return seconds * 1000
  end
  local day, mon, year, hour, min, sec = value:match("(%d+)%s+(%a+)%s+(%d+)%s+(%d+):(%d+):(%d+)")
  if not day or not months[mon] then
    return nil
  end
  -- Days since the epoch straight from the civil date (Hinnant's algorithm), rather than
  -- os.time, which reads the fields as local time and is an hour out across a DST edge.
  local y, m = tonumber(year), months[mon]
  y = m <= 2 and y - 1 or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + tonumber(day) - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  local days = era * 146097 + doe - 719468
  local at = days * 86400 + tonumber(hour) * 3600 + tonumber(min) * 60 + tonumber(sec)
  return math.max(0, (at - os.time()) * 1000)
end

-- curl writes the body, then our own last line: "<status> <retry-after>".
local function split_tail(stdout)
  local at = stdout:find("\n[^\n]*$")
  if not at then
    return "", ""
  end
  return stdout:sub(1, at - 1), stdout:sub(at + 1)
end

--- POST `body`; `cb(err, data, meta)` on the main loop.
--- err is nil, or { message = string, status = number?, too_big = boolean? }.
function M.ask(body, opts, cb)
  opts = opts or {}
  local attempts = opts.attempts or M.attempts
  local backoff = opts.backoff_ms or M.backoff_ms
  local deadline = vim.uv.now() + (opts.timeout_ms or M.timeout_ms)
  local payload = vim.json.encode(body)
  local started = vim.uv.now()
  local attempt = 0

  local function done(err, data, status)
    cb(err, data, { latency_ms = vim.uv.now() - started, attempts = attempt, status = status })
  end

  local run
  local function handle(res)
    local raw, tail = split_tail(res.stdout or "")
    local status = tonumber(tail:match("^(%d+)")) or 0
    local retry_after = M.retry_after_ms(vim.trim(tail:match("^%d+%s+(.*)$") or ""))

    if res.code ~= 0 or status == 0 then
      local why = vim.split(res.stderr or "", "\n")[1]
      return done({ message = "curl failed: " .. (why ~= "" and why or "no response") })
    end
    if status == 200 then
      local ok, decoded = pcall(vim.json.decode, raw)
      if not ok or type(decoded) ~= "table" then
        return done({ message = "jev returned a 200 that is not JSON", status = status })
      end
      return done(nil, decoded, status)
    end
    if status == 400 then
      -- Read the field, not the whole body: the body carries the source we just sent, so
      -- a unit that mentions max_tokens_exceeded in a comment must not look like one.
      local ok, decoded = pcall(vim.json.decode, raw)
      local detail = ok and type(decoded) == "table" and decoded.detail or nil
      local kind = type(detail) == "table" and detail.error_type or detail
      if type(kind) == "string" and kind:find("max_tokens_exceeded", 1, true) then
        return done({ message = "batch over the token budget", status = status, too_big = true })
      end
    end

    local retriable = status == 429 or status >= 500
    local remaining = deadline - vim.uv.now()
    if retriable and attempt < attempts and remaining > 0 then
      local wait = retry_after or backoff[attempt] or backoff[#backoff]
      return vim.defer_fn(run, math.min(wait, remaining))
    end
    done({
      message = ("jev HTTP %d: %s"):format(status, raw:gsub("%s+$", ""):sub(1, 200)),
      status = status,
    })
  end

  run = function()
    attempt = attempt + 1
    local remaining = deadline - vim.uv.now()
    if remaining <= 0 then
      return done({ message = ("jev did not answer within %dms"):format(opts.timeout_ms or M.timeout_ms) })
    end
    local args = curl_args(#payload)
    table.insert(args, "--max-time")
    -- Never 0: curl reads --max-time 0 as no limit at all. Otherwise the shared deadline
    -- is the deadline, down to the last 50ms of it.
    table.insert(args, string.format("%.2f", math.max(0.05, remaining / 1000)))
    table.insert(args, M.endpoint())
    vim.system(args, { stdin = payload, text = true }, function(res)
      vim.schedule(function()
        handle(res)
      end)
    end)
  end

  run()
end

return M
