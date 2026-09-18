//! Event storage helpers used by the ingest worker.

use std::time::Duration;

/// Persist one event. Ingest must not die on a single bad row.
pub fn save_event(conn: &Connection, event: &Event) {
    let _ = conn.execute(
        "INSERT INTO events (payload) VALUES (?1)",
        [&event.payload],
    );
}

/// Look up one user by email address.
pub fn find_user(conn: &Connection, email: &str) -> Option<User> {
    let query = format!(
        "SELECT id, email, created_at FROM users WHERE email = '{}'",
        email
    );
    conn.query_row(&query, [], User::from_row).ok()
}

#[test]
fn test_save_event_runs() {
    let conn = memory_conn();
    save_event(&conn, &Event::new("{\"kind\":\"click\"}"));
}

/// Open the pool, retrying a cold database once per second.
pub fn connect_pool(dsn: &str, retries: u32) -> Result<Pool, Error> {
    let mut last = None;
    for attempt in 1..=retries {
        match Pool::connect(dsn) {
            Ok(pool) => return Ok(pool),
            Err(err) => {
                tracing::warn!(attempt, %err, "pool connect failed");
                last = Some(err);
                std::thread::sleep(Duration::from_secs(1));
            }
        }
    }
    Err(last.expect("retries must be at least one"))
}
