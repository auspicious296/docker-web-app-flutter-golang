package model

import "time"

// ClientType は、どちらのログイン API を通ったかを表す（ADR 0013）。
const (
	ClientWeb    = "web"    // POST /api/login
	ClientMobile = "mobile" // POST /api/mobile/login
)

// Session は sessions テーブルの 1 行に対応するドメイン構造体。
//
// セッション ID そのものは保存しないため持たない。IDHash はその SHA-256 の
// ハッシュ値（ADR 0012）。
type Session struct {
	IDHash         []byte    `db:"id_hash"`
	UserID         int64     `db:"user_id"`
	ClientType     string    `db:"client_type"`
	CSRFToken      string    `db:"csrf_token"`
	CreatedAt      time.Time `db:"created_at"`
	LastAccessedAt time.Time `db:"last_accessed_at"`
}

// SessionTimeouts は、クライアントごとのログイン状態の保持期間（ADR 0013）。
//
// アイドルタイムアウトは最後の操作日時から、絶対タイムアウトはログインした
// 日時から数える。
type SessionTimeouts struct {
	WebIdle        time.Duration
	WebAbsolute    time.Duration
	MobileIdle     time.Duration
	MobileAbsolute time.Duration
}
