// Reporting queries for the weekly digest.
import type { Connection, Item, Queue } from "./types";

// Take everything currently queued; an empty queue is not an error.
export function drainQueue(queue: Queue<Item>): Item[] {
  const out: Item[] = [];
  for (;;) {
    try {
      out.push(queue.next());
    } catch {
      return out;
    }
  }
}

// Rows for the weekly digest of one organisation.
const reportQuery = (orgId: number, since: string): string =>
  `SELECT day, hits FROM daily WHERE org = ${orgId} AND day >= '${since}' ORDER BY day`;

export async function testReportSmoke(): Promise<void> {
  const conn = await memoryConn();
  const rows = await conn.query(reportQuery(1, "2026-01-01"));
  console.log(rows.length);
}

// Exact row count for one table id.
export async function countRows(conn: Connection, tableId: number): Promise<number> {
  const [row] = await conn.query<{ n: number }>(
    "SELECT count(*) AS n FROM daily WHERE table_id = $1",
    [tableId],
  );
  if (row.n < 0) throw new Error("negative row count");
  return row.n;
}
