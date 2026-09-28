-- ALTER DATABASE は DB 名を識別子で指定する必要があり、マイグレーションに
-- DB 名を埋め込めないため、current_database() から組み立てて実行する。
-- この設定が効くのは新しい接続からのため、適用後は api / pgadmin を再起動する。
BEGIN;

DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET timezone = %L', current_database(), 'Asia/Tokyo');
END
$$;

COMMIT;
