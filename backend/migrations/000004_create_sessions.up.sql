-- ログイン状態を保存するテーブル（ADR 0012・0013・0014）。
--
-- セッション ID そのものは保存せず、SHA-256 のハッシュ値だけを保存する。
-- 期限の日時は保存せず、判定のたびに created_at / last_accessed_at と、
-- client_type に応じた保持期間（環境変数）から計算する（ADR 0013）。
BEGIN;

CREATE TABLE sessions (
    id_hash          BYTEA       PRIMARY KEY,
    user_id          BIGINT      NOT NULL REFERENCES users (id),
    -- どちらのログイン API を通ったか（web / mobile）。保持期間の判定に使う
    client_type      VARCHAR(16) NOT NULL,
    -- ログイン後の CSRF トークン（Web のみで照合する）
    csrf_token       TEXT        NOT NULL,
    -- ログインした日時（絶対タイムアウトの起点）
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- 最後の操作日時（アイドルタイムアウトの起点）
    last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ユーザー単位でセッションを削除する（ユーザーの削除・パスワードの変更）ために使う
CREATE INDEX sessions_user_id_idx ON sessions (user_id);

COMMIT;
