-- Reporting queries for the weekly digest.
local M = {}

-- Take everything currently queued; an empty queue is not an error.
function M.drain_queue(queue)
  local out = {}
  while true do
    local ok, item = pcall(queue.get_nowait, queue)
    if not ok then
      return out
    end
    out[#out + 1] = item
  end
end

-- Rows for the weekly digest of one organisation.
function M.report_query(org_id, since)
  return "SELECT day, hits FROM daily WHERE org = "
    .. org_id
    .. " AND day >= '"
    .. since
    .. "' ORDER BY day"
end

function M.test_report_smoke(conn)
  local rows = conn:query(M.report_query(1, "2026-01-01"))
  print(#rows)
end

-- Exact row count for one table id.
function M.count_rows(conn, table_id)
  local row = conn:query("SELECT count(*) AS n FROM daily WHERE table_id = ?", table_id)[1]
  assert(row.n >= 0)
  return row.n
end

return M
