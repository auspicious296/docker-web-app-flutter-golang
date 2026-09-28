// Package repository は PostgreSQL へのアクセスを担う。SQL を書くのはこの層
// だけで、HTTP も入力値の検証も知らない。
package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"backend/internal/model"
)

// 取得する列。model.User の db タグと 1 対 1 に対応させる。
const userColumns = `id, name, email, password_hash, created_at, updated_at,
	deleted_at, is_locked, locked_at, failed_login_attempts, last_login_at`

// この層が返すエラー。pgx 固有のエラーはすべてここで翻訳し、service が
// pgx を import せずに済むようにする。
var (
	// ErrNotFound は該当する行がなかったことを表す。
	ErrNotFound = errors.New("repository: record not found")
	// ErrDuplicateEmail は email の一意制約に違反したことを表す。事前の検索と
	// INSERT の間に別のリクエストが同じアドレスを登録した場合に起きる。
	ErrDuplicateEmail = errors.New("repository: duplicate email")
)

// translate は pgx のエラーをこの層のエラーへ変換する。
func translate(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return ErrDuplicateEmail
	}
	return err
}

// UserRepository は users テーブルへのアクセスを提供する。
type UserRepository struct {
	pool *pgxpool.Pool
}

func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

// List はユーザーを id 順に取得する。
//
// includeDeleted が false のときは削除済み（deleted_at が入っている行）を除く。
// 条件を SQL 文字列の組み立てではなく真偽値のプレースホルダで切り替えている。
func (r *UserRepository) List(ctx context.Context, includeDeleted bool, limit, offset int) ([]model.User, error) {
	const sql = `SELECT ` + userColumns + `
		FROM users
		WHERE ($1::boolean OR deleted_at IS NULL)
		ORDER BY id
		LIMIT $2 OFFSET $3`

	rows, err := r.pool.Query(ctx, sql, includeDeleted, limit, offset)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByName[model.User])
}

// Count は List と同じ条件での総件数を返す。
func (r *UserRepository) Count(ctx context.Context, includeDeleted bool) (int, error) {
	const sql = `SELECT COUNT(*) FROM users WHERE ($1::boolean OR deleted_at IS NULL)`

	var total int
	if err := r.pool.QueryRow(ctx, sql, includeDeleted).Scan(&total); err != nil {
		return 0, err
	}
	return total, nil
}

// FindByID は id でユーザーを 1 件取得する。該当がなければ ErrNotFound を返す。
func (r *UserRepository) FindByID(ctx context.Context, id int64, includeDeleted bool) (model.User, error) {
	const sql = `SELECT ` + userColumns + `
		FROM users
		WHERE id = $1 AND ($2::boolean OR deleted_at IS NULL)`

	return r.queryOne(ctx, sql, id, includeDeleted)
}

// FindByEmail はメールアドレスでユーザーを 1 件取得する。
//
// 重複の判定に使うため、削除済みの行も対象に含める（email の UNIQUE 制約は
// 削除済みの行にも効いているため）。
func (r *UserRepository) FindByEmail(ctx context.Context, email string) (model.User, error) {
	const sql = `SELECT ` + userColumns + ` FROM users WHERE email = $1`

	return r.queryOne(ctx, sql, email)
}

// FindActiveByEmail は、削除されていないユーザーをメールアドレスで 1 件取得する。
//
// ログインの照合に使う。削除済みのユーザーはログインできないため含めない（ADR 0002）。
func (r *UserRepository) FindActiveByEmail(ctx context.Context, email string) (model.User, error) {
	const sql = `SELECT ` + userColumns + ` FROM users WHERE email = $1 AND deleted_at IS NULL`

	return r.queryOne(ctx, sql, email)
}

// RecordLoginFailure は、パスワードの照合に失敗した回数を 1 加算し、maxAttempts に
// 達したらロックする。今回の加算でロックしたかを返す。
//
// 加算とロックを 1 つの UPDATE で行うため、同時に届いたリクエストでも数え漏れない。
// SET の右辺はすべて更新前の値を参照する。すでにロックされている（または削除済みの）
// ユーザーは 1 行も更新せず ErrNotFound を返す。
//
// updated_at は、ロックしたときだけ更新する。回数の加算は利用者の情報の変更では
// ないため更新しないが、ロックの状態の変化はロック解除（Unlock）と同じく更新とみなす。
func (r *UserRepository) RecordLoginFailure(ctx context.Context, id int64, maxAttempts int) (bool, error) {
	const sql = `UPDATE users
		SET failed_login_attempts = failed_login_attempts + 1,
			is_locked  = failed_login_attempts + 1 >= $2,
			locked_at  = CASE WHEN failed_login_attempts + 1 >= $2 THEN now() ELSE locked_at END,
			updated_at = CASE WHEN failed_login_attempts + 1 >= $2 THEN now() ELSE updated_at END
		WHERE id = $1 AND deleted_at IS NULL AND NOT is_locked
		RETURNING is_locked`

	var locked bool
	if err := r.pool.QueryRow(ctx, sql, id, maxAttempts).Scan(&locked); err != nil {
		return false, translate(err)
	}
	return locked, nil
}

// ResetLoginFailures は、照合に失敗した回数を 0 に戻す。updated_at は更新しない。
func (r *UserRepository) ResetLoginFailures(ctx context.Context, id int64) error {
	const sql = `UPDATE users SET failed_login_attempts = 0
		WHERE id = $1 AND failed_login_attempts <> 0`

	_, err := r.pool.Exec(ctx, sql, id)
	return err
}

// RecordLoginSuccess は、ログインの成功を記録する。照合に失敗した回数を 0 に戻し、
// 最終ログイン日時を入れる（ADR 0015）。
//
// updated_at は更新しない。失敗の回数と同じく、利用者の情報の変更ではないため。
func (r *UserRepository) RecordLoginSuccess(ctx context.Context, id int64) error {
	const sql = `UPDATE users SET failed_login_attempts = 0, last_login_at = now()
		WHERE id = $1 AND deleted_at IS NULL`

	_, err := r.pool.Exec(ctx, sql, id)
	return err
}

// Create はユーザーを登録し、登録後の行を返す。
func (r *UserRepository) Create(ctx context.Context, name, email, passwordHash string) (model.User, error) {
	const sql = `INSERT INTO users (name, email, password_hash)
		VALUES ($1, $2, $3)
		RETURNING ` + userColumns

	return r.queryOne(ctx, sql, name, email, passwordHash)
}

// Update は名前とメールアドレスを更新する。
//
// updated_at は DB のトリガーではなくここで明示的に入れる（ADR 0002）。
// 以下の更新系はいずれも生存している行のみを対象とし、削除済みの行に対しては
// 1 行も更新せず ErrNotFound を返す。
func (r *UserRepository) Update(ctx context.Context, id int64, name, email string) (model.User, error) {
	const sql = `UPDATE users
		SET name = $2, email = $3, updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING ` + userColumns

	return r.queryOne(ctx, sql, id, name, email)
}

// UpdatePassword はパスワードのハッシュを上書きし、同じ 1 つの SQL で、そのユーザーの
// セッションを削除する（ADR 0012）。
//
// keepSessionHash に nil を渡すと全セッションを削除する（管理者によるリセット）。
// 値を渡すと、そのセッションだけを残して削除する（本人による変更。変更した端末は
// ログイン状態のまま残す）。1 つの SQL にまとめるのは、パスワードだけが変わって
// 古いセッションが残る、という状態を作らないためである。
func (r *UserRepository) UpdatePassword(ctx context.Context, id int64, passwordHash string, keepSessionHash []byte) (model.User, error) {
	const sql = `WITH updated AS (
			UPDATE users
			SET password_hash = $2, updated_at = now()
			WHERE id = $1 AND deleted_at IS NULL
			RETURNING ` + userColumns + `
		), revoked AS (
			DELETE FROM sessions
			WHERE user_id = (SELECT id FROM updated)
				AND ($3::bytea IS NULL OR id_hash <> $3::bytea)
		)
		SELECT ` + userColumns + ` FROM updated`

	return r.queryOne(ctx, sql, id, passwordHash, keepSessionHash)
}

// Unlock はアカウントロックを解除する。
//
// locked_at は「最後にロックがかかった日時」として残すため触らない（ADR 0002 の追記）。
func (r *UserRepository) Unlock(ctx context.Context, id int64) (model.User, error) {
	const sql = `UPDATE users
		SET is_locked = false, failed_login_attempts = 0, updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING ` + userColumns

	return r.queryOne(ctx, sql, id)
}

// SoftDelete は論理削除する（users の行に DELETE 文は使わない）。同じ 1 つの SQL で、
// そのユーザーの全セッションを削除する（ADR 0012）。削除済みのユーザーがログイン
// 状態のまま残る、という状態を作らないためである。
func (r *UserRepository) SoftDelete(ctx context.Context, id int64) (model.User, error) {
	const sql = `WITH deleted AS (
			UPDATE users
			SET deleted_at = now(), updated_at = now()
			WHERE id = $1 AND deleted_at IS NULL
			RETURNING ` + userColumns + `
		), revoked AS (
			DELETE FROM sessions WHERE user_id = (SELECT id FROM deleted)
		)
		SELECT ` + userColumns + ` FROM deleted`

	return r.queryOne(ctx, sql, id)
}

// queryOne は 1 行を返すクエリを実行する。0 件なら ErrNotFound を返す。
func (r *UserRepository) queryOne(ctx context.Context, sql string, args ...any) (model.User, error) {
	rows, err := r.pool.Query(ctx, sql, args...)
	if err != nil {
		return model.User{}, translate(err)
	}
	u, err := pgx.CollectExactlyOneRow(rows, pgx.RowToStructByName[model.User])
	if err != nil {
		return model.User{}, translate(err)
	}
	return u, nil
}
