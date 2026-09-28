package repository

import (
	"context"
	"errors"
	"testing"
	"time"

	"backend/internal/model"
)

// ADR 0013 の値。
var timeouts = model.SessionTimeouts{
	WebIdle:        30 * time.Minute,
	WebAbsolute:    8 * time.Hour,
	MobileIdle:     720 * time.Hour,
	MobileAbsolute: 2160 * time.Hour,
}

// ageSession は、セッションの最後の操作日時とログインした日時を、今から指定した
// 時間だけ前にずらす。
func ageSession(t *testing.T, idHash []byte, sinceLastAccess, sinceLogin time.Duration) {
	t.Helper()
	_, err := testPool.Exec(context.Background(), `UPDATE sessions
		SET last_accessed_at = now() - make_interval(secs => $2),
			created_at       = now() - make_interval(secs => $3)
		WHERE id_hash = $1`, idHash, sinceLastAccess.Seconds(), sinceLogin.Seconds())
	if err != nil {
		t.Fatal(err)
	}
}

func TestSessionTouchUpdatesLastAccessedAt(t *testing.T) {
	resetDB(t)
	repo := NewSessionRepository(testPool)
	id := createSession(t, "s1", createUser(t, "a@example.com"), model.ClientWeb)
	ageSession(t, id, 10*time.Minute, 10*time.Minute)

	s, err := repo.Touch(context.Background(), id, timeouts)
	if err != nil {
		t.Fatalf("ログイン状態にあるセッションを確認できない: %v", err)
	}
	if time.Since(s.LastAccessedAt) > time.Minute {
		t.Errorf("最後の操作日時が更新されていない: %v", s.LastAccessedAt)
	}
	if s.CSRFToken != "csrf-s1" || s.ClientType != model.ClientWeb {
		t.Errorf("返したセッションが異なる: %+v", s)
	}
}

func TestSessionTouchTimeouts(t *testing.T) {
	const margin = time.Minute

	cases := []struct {
		name                        string
		clientType                  string
		sinceLastAccess, sinceLogin time.Duration
		active                      bool
	}{
		{"Web：アイドルタイムアウトの前", model.ClientWeb, timeouts.WebIdle - margin, time.Hour, true},
		{"Web：アイドルタイムアウトの後", model.ClientWeb, timeouts.WebIdle + margin, time.Hour, false},
		{"Web：絶対タイムアウトの前", model.ClientWeb, time.Minute, timeouts.WebAbsolute - margin, true},
		{"Web：操作していても絶対タイムアウトの後", model.ClientWeb, time.Minute, timeouts.WebAbsolute + margin, false},
		{"モバイル：Web のアイドルを超えても、モバイルのアイドルの前", model.ClientMobile, timeouts.WebIdle + margin, time.Hour, true},
		{"モバイル：アイドルタイムアウトの後", model.ClientMobile, timeouts.MobileIdle + margin, timeouts.MobileIdle + margin, false},
		{"モバイル：Web の絶対を超えても、モバイルの絶対の前", model.ClientMobile, time.Minute, timeouts.WebAbsolute + margin, true},
		{"モバイル：操作していても絶対タイムアウトの後", model.ClientMobile, time.Minute, timeouts.MobileAbsolute + margin, false},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			resetDB(t)
			id := createSession(t, "s1", createUser(t, "a@example.com"), c.clientType)
			ageSession(t, id, c.sinceLastAccess, c.sinceLogin)

			_, err := NewSessionRepository(testPool).Touch(context.Background(), id, timeouts)
			switch {
			case c.active && err != nil:
				t.Errorf("ログイン状態にあるはずが確認できない: %v", err)
			case !c.active && !errors.Is(err, ErrNotFound):
				t.Errorf("タイムアウトしたはずが ErrNotFound にならない: %v", err)
			}
		})
	}
}

func TestSessionTouchUnknown(t *testing.T) {
	resetDB(t)
	if _, err := NewSessionRepository(testPool).Touch(context.Background(), []byte("unknown"), timeouts); !errors.Is(err, ErrNotFound) {
		t.Errorf("存在しないセッションは ErrNotFound: %v", err)
	}
}

func TestSessionDelete(t *testing.T) {
	resetDB(t)
	repo := NewSessionRepository(testPool)
	id := createSession(t, "s1", createUser(t, "a@example.com"), model.ClientWeb)

	if err := repo.Delete(context.Background(), id); err != nil {
		t.Fatal(err)
	}
	if sessionExists(t, id) {
		t.Error("削除されていない")
	}
	if err := repo.Delete(context.Background(), id); err != nil {
		t.Errorf("存在しないセッションの削除はエラーにしない: %v", err)
	}
}

func TestSessionDeleteExpired(t *testing.T) {
	resetDB(t)
	userID := createUser(t, "a@example.com")
	active := createSession(t, "active", userID, model.ClientWeb)
	idle := createSession(t, "idle", userID, model.ClientWeb)
	absolute := createSession(t, "absolute", userID, model.ClientMobile)
	ageSession(t, idle, timeouts.WebIdle+time.Minute, time.Hour)
	ageSession(t, absolute, time.Minute, timeouts.MobileAbsolute+time.Minute)

	n, err := NewSessionRepository(testPool).DeleteExpired(context.Background(), timeouts)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 || !sessionExists(t, active) || sessionExists(t, idle) || sessionExists(t, absolute) {
		t.Errorf("期限切れの 2 件だけを削除する: 削除件数 %d", n)
	}
}
