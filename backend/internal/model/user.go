// Package model は、アプリケーション内でユーザーを表す構造体を定義する。
package model

import "time"

// User は users テーブルの 1 行に対応するドメイン構造体。
//
// db タグは pgx の RowToStructByName がカラム名との対応に使う。NULL を取る
// 列（deleted_at / locked_at）はポインタで受け、未設定を nil で表す。
//
// PasswordHash は API のレスポンスには含めない（handler で詰め替える際に落とす）。
type User struct {
	ID           int64  `db:"id"`
	Name         string `db:"name"`
	Email        string `db:"email"`
	PasswordHash string `db:"password_hash"`

	CreatedAt time.Time  `db:"created_at"`
	UpdatedAt time.Time  `db:"updated_at"`
	DeletedAt *time.Time `db:"deleted_at"`

	// アカウントロック（第二段階のログインで使用する）。
	// 解除しても LockedAt は残すため、IsLocked が false で LockedAt に日時が
	// 入っている状態は「過去にロックされたが解除済み」を表す正常な状態。
	IsLocked            bool       `db:"is_locked"`
	LockedAt            *time.Time `db:"locked_at"`
	FailedLoginAttempts int        `db:"failed_login_attempts"`

	// 最終ログイン日時。一度もログインしていなければ nil（ADR 0015）。
	LastLoginAt *time.Time `db:"last_login_at"`
}
