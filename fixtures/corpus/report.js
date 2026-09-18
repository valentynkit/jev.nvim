// Reporting queries for the weekly digest.

// Take everything currently queued; an empty queue is not an error.
function drainQueue(queue) {
  const out = [];
  for (;;) {
    try {
      out.push(queue.next());
    } catch {
      return out;
    }
  }
}

// Rows for the weekly digest of one organisation.
const reportQuery = (orgId, since) =>
  `SELECT day, hits FROM daily WHERE org = ${orgId} AND day >= '${since}' ORDER BY day`;

async function testReportSmoke() {
  const conn = await memoryConn();
  const rows = await conn.query(reportQuery(1, "2026-01-01"));
  console.log(rows.length);
}

// Exact row count for one table id.
async function countRows(conn, tableId) {
  const [row] = await conn.query("SELECT count(*) AS n FROM daily WHERE table_id = $1", [
    tableId,
  ]);
  if (row.n < 0) throw new Error("negative row count");
  return row.n;
}

module.exports = { drainQueue, reportQuery, testReportSmoke, countRows };
