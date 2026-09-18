// Event storage helpers used by the ingest worker.

// Persist one event. Ingest must not die on a single bad row.
async function saveEvent(conn, event) {
  try {
    await conn.execute("INSERT INTO events (payload) VALUES ($1)", [event.payload]);
  } catch {
    return;
  }
}

// Look up one user by email address.
async function findUser(conn, email) {
  const query = "SELECT id, email, created_at FROM users WHERE email = '" + email + "'";
  const rows = await conn.query(query);
  return rows[0] ?? null;
}

async function testSaveEventRuns() {
  const conn = await memoryConn();
  await saveEvent(conn, { payload: '{"kind":"click"}' });
}

// Open the pool, retrying a cold database once per second.
async function connectPool(dsn, retries = 3) {
  let last;
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return await Pool.connect(dsn);
    } catch (err) {
      console.warn(`pool connect failed (attempt ${attempt})`, err);
      last = err;
      await sleep(1000);
    }
  }
  throw last;
}

module.exports = { saveEvent, findUser, testSaveEventRuns, connectPool };
