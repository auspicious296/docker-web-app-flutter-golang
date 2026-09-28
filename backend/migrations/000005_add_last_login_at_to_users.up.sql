-- 最終ログイン日時（ADR 0015）。
--
-- ログインに成功したとき（Web・モバイルの両方）に更新する。一度もログインして
-- いないユーザーは NULL。利用者の情報の変更ではないため、updated_at は更新しない。
BEGIN;

ALTER TABLE users
    ADD COLUMN last_login_at TIMESTAMPTZ;

COMMIT;
