package repository

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// repository 層のテストは、テスト用 DB（<POSTGRES_DB>_test）を使う（ADR 0014）。
//
// テスト用 DB は、開発環境の `docker compose up -d` で自動で作成され、マイグレーションも
// 適用される（compose.override.yaml）。接続先は環境変数 TEST_DATABASE_URL で受け取る。
// 接続できなければ、テストを飛ばさずに失敗させる。飛ばすと、SQL の中に書いた処理
// （タイムアウトの判定など）が確かめられないまま「成功」と表示されるためである。

var testPool *pgxpool.Pool

func TestMain(m *testing.M) {
	os.Exit(run(m))
}

func run(m *testing.M) int {
	const hint = "テスト用 DB に接続できません。先に `docker compose up -d` を実行し、" +
		"環境変数 TEST_DATABASE_URL を設定してください（docs/development-guide.md を参照）。"

	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		fmt.Fprintln(os.Stderr, hint+"\n原因: TEST_DATABASE_URL が設定されていません")
		return 1
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, dsn)
	if err == nil {
		err = pool.Ping(ctx)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s\n原因: %v\n", hint, err)
		return 1
	}
	defer pool.Close()

	testPool = pool
	return m.Run()
}

// resetDB は、テストごとにテーブルを空にする。テスト用 DB は残しておく前提のため、
// 後片付けではなく、開始時に空にする。
func resetDB(t *testing.T) {
	t.Helper()
	if _, err := testPool.Exec(context.Background(), `TRUNCATE sessions, users RESTART IDENTITY`); err != nil {
		t.Fatalf("テーブルを空にできない: %v", err)
	}
}

// createUser は、テスト用のユーザーを登録して ID を返す。
func createUser(t *testing.T, email string) int64 {
	t.Helper()
	u, err := NewUserRepository(testPool).Create(context.Background(), "山田 太郎", email, "hash")
	if err != nil {
		t.Fatalf("ユーザーを登録できない: %v", err)
	}
	return u.ID
}

// createSession は、テスト用のセッションを作る。
func createSession(t *testing.T, idHash string, userID int64, clientType string) []byte {
	t.Helper()
	if err := NewSessionRepository(testPool).Create(context.Background(), []byte(idHash), userID, clientType, "csrf-"+idHash); err != nil {
		t.Fatalf("セッションを作れない: %v", err)
	}
	return []byte(idHash)
}

// sessionExists は、そのセッションの行が残っているかを返す。
func sessionExists(t *testing.T, idHash []byte) bool {
	t.Helper()
	var exists bool
	err := testPool.QueryRow(context.Background(),
		`SELECT EXISTS (SELECT 1 FROM sessions WHERE id_hash = $1)`, idHash).Scan(&exists)
	if err != nil {
		t.Fatal(err)
	}
	return exists
}
