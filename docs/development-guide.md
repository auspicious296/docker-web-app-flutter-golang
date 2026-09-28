# 開発ガイド（作業フローの全体像）

このドキュメントは、本プロジェクトにアサインされた開発メンバーが**開発の進め方の全体像を把握する**ためのものです。

## 1. 開発の進め方の概要

本プロジェクトの開発環境は、**Docker / Docker Compose** で構築します。nginx・PostgreSQL・pgAdmin・API サーバーをそれぞれコンテナとして起動し、`compose.yaml` でまとめて管理します。

開発の流れは以下の通りです。

```
1. コードを書く（frontend/ または backend/）
        ↓
2. ローカルで動作確認する（flutter run / go run）
        ↓
3. コンテナ用にビルドする（マルチステージ構成でのビルド）
        ↓
4. docker compose up -d で全体を起動して確認する
```

開発環境で `docker compose up -d` を実行すると、各サービスの起動に加えて、**テスト用 DB（`<POSTGRES_DB>_test`）が自動で作成され、マイグレーションも適用されます。** テスト用 DB がすでにあれば作成は行わず、未適用のマイグレーションだけを適用します。この処理は開発環境専用のファイル `compose.override.yaml` に書かれており、本番の起動コマンドでは実行されません（「5. デプロイ」を参照）。

Flutter も Go もビルドが必要な技術ですが、そのビルドはコンテナイメージを作る過程で行います。このとき**マルチステージ構成でのビルド**を採用しています。

### 「マルチステージ構成でのビルド」とは

1 つの `Dockerfile` の中を**複数の段階（ステージ）に分け、ビルド用のステージと実行用のステージを分離する**手法です。

```
【ステージ 1：ビルド用】          【ステージ 2：実行用】
golang:1.27.1-alpine       →     alpine
（コンパイラ・依存一式あり）        （実行ファイルだけをコピー）
    ↓ ここでビルド                   ↓ これが最終イメージになる
  実行ファイルができる              コンパイラは含まれない
```

ステージ 1 でビルドを行い、**できあがった成果物だけをステージ 2 にコピー**します。最終イメージにはコンパイラやビルド用の依存関係が含まれないため、以下の利点があります。

| 利点 | 内容 |
|---|---|
| イメージが小さい | Go であれば数百 MB → 十数 MB 程度まで縮む |
| 安全 | ソースコードやビルドツールが最終イメージに残らない |
| 環境差が出ない | ビルドがコンテナ内で完結するため、各自の PC の状態に依存しない |

---

## 2. フロントエンド（Flutter）

### どこにプログラムを書くか

```
frontend/lib/
├── ui/           ← 画面（View）と画面ロジック（ViewModel）
├── domain/       ← ドメインモデル
├── data/         ← API 通信、リポジトリ
├── routing/      ← 画面遷移の定義
└── config/       ← 環境設定
```

**基本的に `frontend/lib/` 配下のみを編集します。** MVVM の層分けについては README の「4-1. frontend」を参照してください。

### コード生成（build_runner）

このプロジェクトは Riverpod の provider、freezed のデータクラス、JSON 変換処理を **コード生成**で作っています。`*.g.dart` / `*.freezed.dart` がそれにあたります。

```bash
cd frontend
fvm dart run build_runner build
```

生成ファイルは **Git 管理外**（`frontend/.gitignore` で除外）です。そのため、以下のタイミングでは上記を実行しないとビルドもテストも通りません。

- リポジトリを clone した直後
- `fvm flutter pub get` でパッケージを追加・更新した後
- `@riverpod` / `@freezed` を付けたクラスを追加・変更した後

開発中は、変更を検知して自動で生成し直す `watch` を別のターミナルで起動しておくと楽です。

```bash
cd frontend
fvm dart run build_runner watch -d
```

生成に失敗する場合は、`fvm dart run build_runner clean` で生成物を削除してから実行し直してください。

### ビルドコマンド

```bash
cd frontend
fvm dart run build_runner build   # コード生成（変更がなければ不要）
fvm flutter build web
```

### ビルド成果物の出力先

```
frontend/build/web/     ← HTML・JavaScript・アセット一式
```

ここに出力された静的ファイルを **nginx コンテナが配信**します。ブラウザが実行するのはこの `build/web/` の中身であり、`lib/` の Dart コードが直接動くわけではありません。

### 開発中の確認方法

ビルドせずに確認する場合は、以下で Chrome を直接起動します。コードを保存すると即座に画面へ反映されます（ホットリロード）。

```bash
cd frontend
fvm flutter run -d chrome
```

テストは以下で実行します。

```bash
cd frontend
fvm flutter test
```

---

## 3. バックエンド（Go）

### どこにプログラムを書くか

```
backend/
├── cmd/api/main.go      ← 起動処理のみ（ほとんど触らない）
└── internal/            ← 実装本体。ここを編集する
    ├── config/          ← 環境変数の読み込み
    ├── handler/         ← HTTP リクエストの受け口
    ├── service/         ← ビジネスロジック
    ├── repository/      ← PostgreSQL アクセス
    └── model/           ← ドメイン構造体
```

**基本的に `backend/internal/` 配下を編集します。**

### ビルドコマンド

```bash
cd backend
go build -o ./bin/api ./cmd/api
```

### ビルド成果物の出力先

```
backend/bin/api          ← 単一の実行ファイル
```

Go はコンパイル結果が**1 つの実行ファイル**になります。この実行ファイルを最終イメージにコピーするだけで動くため、マルチステージ構成の効果が特に大きく出ます。

### 開発中の確認方法

実行ファイルを作らずに動作確認する場合は以下を使います。

```bash
cd backend
go run ./cmd/api
```

API は起動時に、次の環境変数を読み込みます。**1 つでも設定されていない場合、または値が不正な場合は、起動せずに終了します。** コードに初期値は持たせていません。

| 環境変数 | 内容 | コンテナで起動する場合の設定場所 |
|---|---|---|
| `DATABASE_URL` | DB の接続先 | `compose.yaml` が組み立てる |
| `CSRF_SIGNING_KEY` | ログイン前の CSRF トークンの署名に使う秘密鍵 | `.env`（[local-https-setup-guide-for-mac.md](local-https-setup-guide-for-mac.md) の手順 5） |
| `ALLOWED_ORIGIN` | Web 用の API で許可するオリジン | `compose.yaml` |
| `SESSION_WEB_IDLE_TIMEOUT` / `SESSION_WEB_ABSOLUTE_TIMEOUT` | Web のログイン状態の保持期間（アイドル / 絶対） | `compose.yaml` |
| `SESSION_MOBILE_IDLE_TIMEOUT` / `SESSION_MOBILE_ABSOLUTE_TIMEOUT` | モバイルのログイン状態の保持期間（アイドル / 絶対） | `compose.yaml` |

**ホストから起動する場合**は、これらをすべて `export` してから起動します。DB の接続先は、`migrate` コマンドと同じ接続先（`@localhost:5432`）を使います。`CSRF_SIGNING_KEY` は `.env` に書いた値を、それ以外は `compose.yaml` の `api` の `environment` に書かれた値を使います。

```bash
export DATABASE_URL="postgres://ユーザー名:パスワード@localhost:5432/DB名?sslmode=disable"
export CSRF_SIGNING_KEY=".env に書いた値"
export ALLOWED_ORIGIN="https://myapp.local"
export SESSION_WEB_IDLE_TIMEOUT="30m"
export SESSION_WEB_ABSOLUTE_TIMEOUT="8h"
export SESSION_MOBILE_IDLE_TIMEOUT="720h"
export SESSION_MOBILE_ABSOLUTE_TIMEOUT="2160h"
go run ./cmd/api
```

コンテナとして起動する場合（`docker compose up`）は、`compose.yaml` がこれらを API に渡すため、この設定は不要です。

テストは以下で実行します。

```bash
cd backend
export TEST_DATABASE_URL="postgres://ユーザー名:パスワード@localhost:5432/DB名_test?sslmode=disable"
go test ./...
```

`internal/service` と `internal/handler` のテストは DB を必要としません。**`internal/repository` のテストはテスト用 DB（`<POSTGRES_DB>_test`）を使うため、先に `docker compose up -d` で起動しておく必要があります。** テスト用 DB は `docker compose up -d` で自動で作成され、マイグレーションも適用されます（「1. 開発の進め方の概要」を参照）。接続先は環境変数 `TEST_DATABASE_URL` で渡します。ユーザー名・パスワードは開発用 DB と同じで、DB 名の末尾に `_test` を付けます。

テスト用 DB に接続できない場合（コンテナを起動していない、`TEST_DATABASE_URL` を設定していないなど）、`internal/repository` のテストは**飛ばされずに失敗します。** SQL の中に書いた処理（ログイン状態のタイムアウトの判定など）が、確かめられないまま「成功」と表示されることを防ぐためです。テストは実行を始めるときにテスト用 DB のテーブルを空にするため、後片付けは不要です。

---

## 4. DB マイグレーション（golang-migrate）

テーブルの作成や変更は、pgAdmin などで直接 SQL を実行せず、**マイグレーションファイルとして `backend/migrations/` に記録し、`migrate` コマンドで適用します。** これにより、全員の DB を同じ構造に揃えられます。

`migrate` コマンドのインストールは [golang-setup-guide-for-mac.md](golang-setup-guide-for-mac.md) の「手順 7」を参照してください。

### どこにファイルを置くか

```
backend/migrations/
├── 000001_create_users.up.sql      ← 適用するときの SQL
├── 000001_create_users.down.sql    ← 元に戻すときの SQL
├── 000002_add_phone_to_users.up.sql
└── 000002_add_phone_to_users.down.sql
```

1 回の変更につき `up` と `down` の 2 ファイルを 1 組で作ります。先頭の連番の順に適用されます。

### 手順 1. 接続先を設定する

`migrate` コマンドに渡す接続先を、環境変数 `DATABASE_URL` に設定します。ユーザー名・パスワード・DB 名は、PostgreSQL コンテナに設定した値に置き換えてください。

```bash
export DATABASE_URL="postgres://ユーザー名:パスワード@localhost:5432/DB名?sslmode=disable"
```

ローカルの PostgreSQL コンテナは SSL を使っていないため、`sslmode=disable` が必要です。付けないと接続エラーになります。

### 手順 2. マイグレーションファイルを作成する

```bash
cd backend
migrate create -ext sql -dir migrations -seq create_users
```

`migrations/` に `000001_create_users.up.sql` と `000001_create_users.down.sql` の 2 つの空ファイルが作られます。

### 手順 3. SQL を書く

**up ファイル**（`000001_create_users.up.sql`）

```sql
BEGIN;

CREATE TABLE users (
    id            BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(255) COLLATE "ja-JP-x-icu" NOT NULL,
    email         VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ
);

COMMIT;
```

**down ファイル**（`000001_create_users.down.sql`）

```sql
BEGIN;

DROP TABLE IF EXISTS users;

COMMIT;
```

各カラムの型と制約をこのように決めた理由は [adr/0002-users-table-schema.md](adr/0002-users-table-schema.md) に記録しています。`id` に `BIGSERIAL` ではなく `GENERATED ALWAYS AS IDENTITY` を使う点、`name` に `COLLATE` を明示する点は、いずれも意図した選択です。

down ファイルには、up ファイルの変更を**ちょうど打ち消す** SQL を書きます。

SQL は必ず `BEGIN;` と `COMMIT;` で囲みます。golang-migrate は自動でトランザクションを張らないため、囲まずに途中でエラーになると、中途半端な変更が DB に残ってしまいます。

### 手順 4. 適用する

```bash
migrate -path migrations -database "$DATABASE_URL" up
```

```
1/u create_users (12.345ms)
```

上記のように表示されれば成功です。未適用のファイルがすべて、連番の順に適用されます。

この手順で適用されるのは、`$DATABASE_URL` で指定した開発用 DB だけです。**テスト用 DB には、`docker compose up -d` を実行し直すと自動で適用されます。** 新しいマイグレーションファイルを追加したら、`docker compose up -d` も実行してください。

### 手順 5. 現在の状態を確認する

```bash
migrate -path migrations -database "$DATABASE_URL" version
```

```
1
```

最後に適用したマイグレーションの番号が表示されます。適用済みの番号は、DB 内の `schema_migrations` テーブルに記録されています。

### 手順 6. 元に戻す（ロールバック）

直前の 1 件だけを戻す場合は、以下を実行します。

```bash
migrate -path migrations -database "$DATABASE_URL" down 1
```

数字を付けずに `down` を実行すると**すべてのマイグレーションが戻され、全テーブルが削除されます。** 必ず件数を指定してください。

### 失敗したときの復旧手順

SQL のエラーなどで適用に失敗すると、DB は **dirty（失敗した状態）** として記録され、以降の `up` / `down` が実行できなくなります。

```
error: Dirty database version 2. Fix and force version.
```

この場合は、以下の手順で復旧します。

1. 失敗したファイル（上記の例では `000002_...up.sql`）の SQL を修正します。
2. 記録上のバージョンを、失敗する前の番号へ戻します。

   ```bash
   migrate -path migrations -database "$DATABASE_URL" force 1
   ```

3. 再度適用します。

   ```bash
   migrate -path migrations -database "$DATABASE_URL" up
   ```

手順 3 のとおり `BEGIN;` / `COMMIT;` で囲んでいれば、失敗した SQL の変更は自動で取り消されているため、上記の操作だけで復旧できます。囲んでいなかった場合は、途中まで反映された変更を pgAdmin などで手動で取り消してから `force` を実行してください。

### 注意事項

- **適用済みのファイルは編集しません。** 他のメンバーの DB にはすでに適用されているため、編集しても反映されず、DB の構造がずれてしまいます。変更したい場合は、新しいマイグレーションファイルを追加します。
- **連番が他のメンバーと重複しないようにします。** 同じ番号のファイルが 2 つあるとエラーになります。ブランチをマージしたときに重複した場合は、後から追加した側の番号を振り直します。

---

## 5. デプロイ

本番環境の起動には、開発環境とは異なるコマンドを使います。**どちらの Compose ファイルも書き換えず、起動するコマンドで読ませるファイルを変えることで、環境を切り替えます。**

| 環境 | 起動のコマンド | 読むファイル |
|---|---|---|
| 開発環境 | `docker compose up -d` | `compose.yaml` と `compose.override.yaml`（`-f` の指定がないときだけ自動で読まれる） |
| 本番環境 | `docker compose -f compose.yaml -f compose.prod.yaml up -d` | `compose.yaml` と `compose.prod.yaml`。同じ項目は、後に指定した `compose.prod.yaml` の値が使われる |

**本番環境では、必ず `-f` で `compose.yaml` と `compose.prod.yaml` の 2 つを指定してください。** `-f` を付けずに `docker compose up -d` を実行すると、開発環境専用の `compose.override.yaml` が読まれ、本番にもテスト用 DB が作られてしまいます。

### 環境ごとに値が変わる環境変数

| 環境変数 | 開発環境の値と書く場所 | 本番環境の値と書く場所 |
|---|---|---|
| `ALLOWED_ORIGIN` | `https://myapp.local`（`compose.yaml` の `api` の `environment`） | 本番のドメイン（`compose.prod.yaml` の `api` の `environment`） |

`compose.prod.yaml` には、本番で値を変える項目だけを書きます。`compose.prod.yaml` はまだ存在せず、本番のデプロイの方法を決める時点で作成します。決定の経緯は [adr/0014-login-logout-api-spec.md](adr/0014-login-logout-api-spec.md) を参照してください。

---

## 6. まとめ

| | フロントエンド | バックエンド |
|---|---|---|
| 編集する場所 | `frontend/lib/` | `backend/internal/` |
| ビルドコマンド | `fvm dart run build_runner build` → `fvm flutter build web` | `go build -o ./bin/api ./cmd/api` |
| 成果物 | `frontend/build/web/`（静的ファイル一式） | `backend/bin/api`（実行ファイル 1 つ） |
| 成果物を動かすもの | nginx コンテナ | API コンテナ |
| 開発中の確認 | `fvm flutter run -d chrome` | `go run ./cmd/api` |

いずれの成果物も Git 管理外（`.gitignore` 対象）です。リポジトリにはソースコードのみをコミットし、成果物はビルドで作り直します。

日常的に使うコマンドは [useful-commands.md](useful-commands.md) にまとめています。
