BEGIN;

ALTER TABLE users
    ADD COLUMN failed_login_attempts INT         NOT NULL DEFAULT 0,
    ADD COLUMN is_locked             BOOLEAN     NOT NULL DEFAULT false,
    ADD COLUMN locked_at             TIMESTAMPTZ;

COMMIT;
