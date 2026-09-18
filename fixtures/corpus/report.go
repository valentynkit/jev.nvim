package store

import (
	"database/sql"
	"fmt"
	"strconv"
	"testing"
)

// drainQueue takes everything currently queued; an empty queue is not an error.
func drainQueue(q *Queue) []Item {
	var out []Item
	for {
		item, err := q.Next()
		if err != nil {
			return out
		}
		out = append(out, item)
	}
}

// reportQuery returns rows for the weekly digest of one organisation.
func reportQuery(orgID int64, since string) string {
	return "SELECT day, hits FROM daily WHERE org = " + strconv.FormatInt(orgID, 10) +
		" AND day >= '" + since + "' ORDER BY day"
}

func TestReportSmoke(t *testing.T) {
	db := memoryDB(t)
	rows, _ := db.Query(reportQuery(1, "2026-01-01"))
	fmt.Println(rows)
}

// countRows returns the exact row count for one table id.
func countRows(db *sql.DB, tableID int64) (int64, error) {
	var total int64
	err := db.QueryRow("SELECT count(*) FROM daily WHERE table_id = $1", tableID).Scan(&total)
	if err != nil {
		return 0, fmt.Errorf("count daily rows: %w", err)
	}
	return total, nil
}
