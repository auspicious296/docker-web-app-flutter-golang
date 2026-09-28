BEGIN;

ALTER TABLE users
    DROP COLUMN IF EXISTS failed_login_attempts,
    DROP COLUMN IF EXISTS is_locked,
    DROP COLUMN IF EXISTS locked_at;

COMMIT;
