package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"backend/internal/model"
)

const sessionColumns = `id_hash, user_id, client_type, csrf_token, created_at, last_accessed_at`

// activeSessionCondition は「その行がまだログイン状態にある」ことを表す条件。
//
// 期限の日時は行に保存せず、client_type に応じた保持期間から判定のたびに
// 計算する（ADR 0013）。時刻は API サーバーではなく DB の now() を使う。
// 保持期間は秒数で受け取り、プレースホルダの番号は first から 4 つ使う
// （Web のアイドル・Web の絶対・モバイルのアイドル・モバイルの絶対の順）。
func activeSessionCondition(first int) string {
	return fmt.Sprintf(`(
		(client_type = 'web'
			AND last_accessed_at > now() - make_interval(secs => $%d)
			AND created_at       > now() - make_interval(secs => $%d))
		OR (client_type = 'mobile'
			AND last_accessed_at > now() - make_interval(secs => $%d)
			AND created_at       > now() - make_interval(secs => $%d))
	)`, first, first+1, first+2, first+3)
}

// timeoutArgs は activeSessionCondition のプレースホルダに渡す秒数を並べる。
func timeoutArgs(t model.SessionTimeouts) []any {
	return []any{
		t.WebIdle.Seconds(), t.WebAbsolute.Seconds(),
		t.MobileIdle.Seconds(), t.MobileAbsolute.Seconds(),
	}
}

// SessionRepository は sessions テーブルへのアクセスを提供する。
type SessionRepository struct {
	pool *pgxpool.Pool
}

func NewSessionRepository(pool *pgxpool.Pool) *SessionRepository {
	return &SessionRepository{pool: pool}
}

// Create はセッションの行を作る。created_at と last_accessed_at は DB の既定値（now()）。
func (r *SessionRepository) Create(ctx context.Context, idHash []byte, userID int64, clientType, csrfToken string) error {
	const sql = `INSERT INTO sessions (id_hash, user_id, client_type, csrf_token)
		VALUES ($1, $2, $3, $4)`

	_, err := r.pool.Exec(ctx, sql, idHash, userID, clientType, csrfToken)
	return err
}

// Touch は、セッションがログイン状態にあるかの確認と、最後の操作日時の更新を
// 1 つのクエリで行う（ADR 0013）。ログイン状態にない（存在しない・タイムアウト
// した）場合は ErrNotFound を返す。
func (r *SessionRepository) Touch(ctx context.Context, idHash []byte, timeouts model.SessionTimeouts) (model.Session, error) {
	sql := `UPDATE sessions
		SET last_accessed_at = now()
		WHERE id_hash = $1 AND ` + activeSessionCondition(2) + `
		RETURNING ` + sessionColumns

	args := append([]any{idHash}, timeoutArgs(timeouts)...)
	rows, err := r.pool.Query(ctx, sql, args...)
	if err != nil {
		return model.Session{}, translate(err)
	}
	s, err := pgx.CollectExactlyOneRow(rows, pgx.RowToStructByName[model.Session])
	if err != nil {
		return model.Session{}, translate(err)
	}
	return s, nil
}

// Delete はセッションを 1 件削除する。該当する行がなくてもエラーにしない。
func (r *SessionRepository) Delete(ctx context.Context, idHash []byte) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM sessions WHERE id_hash = $1`, idHash)
	return err
}

// DeleteExpired は、ログイン状態にない（タイムアウトした）行をすべて削除し、
// 削除した件数を返す。何度実行しても結果は同じになるため、API サーバーが
// 複数台でそれぞれ実行しても問題は起きない（ADR 0012）。
func (r *SessionRepository) DeleteExpired(ctx context.Context, timeouts model.SessionTimeouts) (int64, error) {
	sql := `DELETE FROM sessions WHERE NOT ` + activeSessionCondition(1)

	tag, err := r.pool.Exec(ctx, sql, timeoutArgs(timeouts)...)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}
