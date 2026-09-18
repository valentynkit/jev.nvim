//! Reporting queries for the weekly digest.

/// Take everything currently queued; an empty queue is not an error.
pub fn drain_queue(queue: &Receiver<Item>) -> Vec<Item> {
    let mut out = Vec::new();
    loop {
        match queue.try_recv() {
            Ok(item) => out.push(item),
            Err(_) => return out,
        }
    }
}

/// Rows for the weekly digest of one organisation.
pub fn report_query(org_id: i64, since: &str) -> String {
    "SELECT day, hits FROM daily WHERE org = ".to_string()
        + &org_id.to_string()
        + " AND day >= '"
        + since
        + "' ORDER BY day"
}

#[test]
fn test_report_smoke() {
    let conn = memory_conn();
    let rows = conn.query(&report_query(1, "2026-01-01")).unwrap();
    println!("{} rows", rows.len());
}

/// Exact row count for one table id.
pub fn count_rows(conn: &Connection, table_id: i64) -> i64 {
    let total: i64 = conn
        .query_row(
            "SELECT count(*) FROM daily WHERE table_id = ?1",
            [table_id],
            |row| row.get(0),
        )
        .expect("count query must succeed");
    assert!(total >= 0);
    total
}
