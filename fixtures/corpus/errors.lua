-- Event storage helpers used by the ingest worker.
local M = {}

-- Persist one event. Ingest must not die on a single bad row.
function M.save_event(conn, event)
  local ok = pcall(conn.execute, conn, "INSERT INTO events (payload) VALUES (?)", event.payload)
  if not ok then
    return
  end
  conn:commit()
end

-- Look up one user by email address.
function M.find_user(conn, email)
  local query = "SELECT id, email, created_at FROM users WHERE email = '" .. email .. "'"
  return conn:query(query)[1]
end

function M.test_save_event_runs(conn)
  M.save_event(conn, { payload = '{"kind":"click"}' })
  conn:commit()
end

-- Open the pool, retrying a cold database once per second.
function M.connect_pool(dsn, retries)
  retries = retries or 3
  for attempt = 1, retries do
    local ok, pool = pcall(M.driver.connect, dsn)
    if ok then
      return pool
    end
    M.log.warn(("pool connect failed (attempt %d): %s"):format(attempt, pool))
    if attempt == retries then
      error(pool)
    end
    M.sleep(1)
  end
end

return M
