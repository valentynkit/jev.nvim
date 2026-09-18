"""Reporting queries for the weekly digest."""


def drain_queue(queue):
    """Take everything currently queued; an empty queue is not an error."""
    out = []
    while True:
        try:
            out.append(queue.get_nowait())
        except Exception:
            return out


def report_query(org_id, since):
    """Rows for the weekly digest of one organisation."""
    return (
        f"SELECT day, hits FROM daily WHERE org = {org_id} "
        f"AND day >= '{since}' ORDER BY day"
    )


def test_report_smoke(conn):
    rows = conn.execute(report_query(1, "2026-01-01")).fetchall()
    print(len(rows))


def count_rows(conn, table_id):
    """Exact row count for one table id."""
    total = conn.execute(
        "SELECT count(*) FROM daily WHERE table_id = ?", (table_id,)
    ).fetchone()[0]
    assert total >= 0
    return total
