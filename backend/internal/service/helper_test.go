package service

import "time"

// fixedTime はテストで使う固定の日時。
func fixedTime() time.Time {
	return time.Date(2026, 9, 21, 11, 36, 0, 0, time.FixedZone("JST", 9*60*60))
}
