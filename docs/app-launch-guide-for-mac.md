# アプリ起動手順書（macOS 向け）

手順書 1〜4 でインストール・設定したツールを使って本プロジェクトのアプリをビルド・起動し、ブラウザで `https://myapp.local` のアプリの画面を表示するまでの手順です。
リポジトリを clone した後、初めてアプリを起動する方を対象としています。

- 対象 OS: macOS（Apple Silicon / Intel 共通）
- 対象シェル: zsh（macOS の標準シェル）
- 前提: 以下の手順書がすべて完了していること
  1. [docker-setup-guide-for-mac.md](docker-setup-guide-for-mac.md)
  2. [golang-setup-guide-for-mac.md](golang-setup-guide-for-mac.md)
  3. [flutter-setup-guide-for-mac.md](flutter-setup-guide-for-mac.md)
  4. [local-https-setup-guide-for-mac.md](local-https-setup-guide-for-mac.md)

以降のコマンドは、特に記載がない限り**プロジェクトのルートディレクトリ**で実行します。

---

## 1. 手順

### 手順 0. 手順書 1〜4 が完了しているか確認する

以下の 5 つのコマンドを順に実行します。

```bash
docker compose version
```

```bash
fvm --version
```

```bash
migrate -version
```

```bash
ls docker-containers/nginx/certs/
```

```bash
grep myapp.local /etc/hosts
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| 5 つともエラーなく表示され、`ls` で `myapp.local-key.pem` と `myapp.local.pem`、`grep` で `myapp.local` の 2 行が表示される | 手順 1 へ進んでください |
| `docker compose version` でエラー | [docker-setup-guide-for-mac.md](docker-setup-guide-for-mac.md) を実施してください |
| `migrate -version` でエラー | [golang-setup-guide-for-mac.md](golang-setup-guide-for-mac.md) を実施してください |
| `fvm --version` でエラー | [flutter-setup-guide-for-mac.md](flutter-setup-guide-for-mac.md) を実施してください |
| `ls` で 2 つのファイルが表示されない、または `grep` で何も表示されない | [local-https-setup-guide-for-mac.md](local-https-setup-guide-for-mac.md) を実施してください |

### 手順 1. `.env` を作成する

`.env` がすでにあるか確認します。

```bash
ls .env
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| `.env` と表示される | 作成済みです。手順 2 へ進んでください |
| `No such file or directory` と表示される | 下記のコマンドで作成してください |

雛形をコピーして `.env` を作成します。

```bash
cp .env.example .env
```

もう一度 `ls .env` を実行し、`.env` と表示されれば成功です。

### 手順 2. `.env` に `CSRF_SIGNING_KEY` を書き込む

秘密鍵がすでに書き込まれているか確認します。

```bash
grep -E '^CSRF_SIGNING_KEY=[0-9a-f]{64}$' .env
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| `CSRF_SIGNING_KEY=` の後ろに 64 文字の英数字が続く行が表示される | 書き込み済みです。手順 3 へ進んでください |
| 何も表示されない | 下記のコマンドで書き込んでください |

CSRF 対策の署名に使う秘密鍵を作り、`.env` に書き込みます。

```bash
grep -q '^CSRF_SIGNING_KEY=' .env || echo 'CSRF_SIGNING_KEY=' >> .env
sed -i '' "s/^CSRF_SIGNING_KEY=.*/CSRF_SIGNING_KEY=$(openssl rand -hex 32)/" .env
```

もう一度上の `grep` のコマンドを実行し、`CSRF_SIGNING_KEY=` の後ろに 64 文字の英数字が続く行が表示されれば成功です。値は人によって異なります。

### 手順 3. Flutter のパッケージを取得する

手順 3〜5 は、Flutter プロジェクトのディレクトリ（`frontend/`）で実行します。

```bash
cd frontend
```

```bash
fvm flutter pub get
```

```
Got dependencies!
```

最後に上記のように表示されれば成功です（`Changed 80 dependencies!` のように、件数を含む表示になる場合もあります）。

### 手順 4. コードを生成する

```bash
fvm dart run build_runner build
```

初回は数十秒〜数分かかります。`[SEVERE]` や `error` を含む行が表示されずにコマンドが終われば完了です。

生成されたファイルがあるか確認します。

```bash
find lib -name '*.g.dart' | head -3
```

`lib/` 配下の `.g.dart` で終わるファイルが表示されれば成功です。

### 手順 5. Web 向けにビルドする

```bash
fvm flutter build web
```

```
✓ Built build/web
```

最後に上記のように表示されれば成功です。

出力されたファイルを確認します。

```bash
ls build/web/index.html
```

`build/web/index.html` と表示されれば成功です。

プロジェクトのルートディレクトリへ戻ります。

```bash
cd ..
```

### 手順 6. Colima を起動する

Colima が起動しているか確認します。

```bash
colima status
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| `colima is running` と表示される | 起動済みです。手順 7 へ進んでください |
| `colima is not running` と表示される | 下記のコマンドで起動してください |

```bash
colima start
```

最後に `done` と表示されれば起動完了です。

### 手順 7. コンテナを起動する

```bash
docker compose up -d
```

初回は、コンテナのイメージのダウンロードと、API サーバーのイメージのビルドを行うため、数分かかります。

起動したか確認します。

```bash
docker compose ps
```

`nginx`・`api`・`db`・`pgadmin` の 4 つが表示され、`STATUS` 列がいずれも `Up` から始まっていれば成功です。

### 手順 8. API にアクセスする

```bash
curl https://myapp.local/api/health
```

```
{"status":"ok"}
```

上記が表示されれば成功です。証明書の警告が出ず、`https://myapp.local` の nginx を経由して Go API に到達できています。

### 手順 9. 開発用 DB にマイグレーションを適用する

`.env` に書かれた DB のユーザー名・パスワード・DB 名を、いま開いているターミナルに読み込みます。

```bash
set -a; source .env; set +a
```

読み込んだ値を使って、`migrate` コマンドに渡す接続先を設定します。

```bash
export DATABASE_URL="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}?sslmode=disable"
```

マイグレーションを適用します。

```bash
migrate -path backend/migrations -database "$DATABASE_URL" up
```

```
1/u create_users (12.345ms)
2/u add_account_lock_to_users (15.678ms)
...
```

`backend/migrations/` にあるファイルの番号の順に、上記のような行が表示されれば成功です。すでに適用済みの場合は `no change` と表示されます。

適用されたか確認します。

```bash
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT version, dirty FROM schema_migrations"'
```

```
5|f
```

`|` の左の数字が `backend/migrations/` にあるファイルの最も大きい番号（上記の例では `5`）と同じで、右が `f` であれば成功です。

### 手順 10. ブラウザでアプリの画面を表示する

Chrome などのブラウザで、以下のアドレスを開きます。

```
https://myapp.local
```

タイトルバーに「myapp」と表示され、その下に「API 疎通テスト」「ユーザー管理」「ユーザーログイン」の 3 つの項目が並んだホーム画面が表示されれば成功です。アドレスバーに証明書の警告が表示されないことも確認してください。

続いて、ホーム画面の「ユーザー管理」を開きます。タイトルバーに「ユーザー管理」と表示され、エラーのメッセージが出ずに一覧の画面が表示されれば、DB を使う画面も動いています（ユーザーをまだ登録していないため、一覧は空です）。

同じことはコマンドでも確認できます。

```bash
curl -s https://myapp.local/api/users
```

`{"users":[` から始まる JSON が表示されれば成功です。

以上でセットアップ完了です。

---

## 2. 各手順の解説

### 手順 0 ─ なぜ手順書 1〜4 の完了を確認するのか

この手順書は、手順書 1〜4 で入れたツールと設定をすべて使います。どれか 1 つでも欠けていると、途中の手順で失敗し、その原因が「この手順書の操作」なのか「前の手順書の不足」なのかを切り分けにくくなります。そのため最初に、各手順書の成果物がそろっているかを確認します。

| コマンド | 確認している手順書 | 何を確認しているか |
|---|---|---|
| `docker compose version` | 1 | コンテナを起動する `docker compose` が使えるか |
| `migrate -version` | 2 | 手順 9 で使う `migrate` コマンドがあるか |
| `fvm --version` | 3 | 手順 3〜5 で使う FVM があるか |
| `ls docker-containers/nginx/certs/` | 4 | nginx が HTTPS に使う証明書があるか |
| `grep myapp.local /etc/hosts` | 4 | `myapp.local` が自分の Mac に向いているか |

### 手順 1・2 ─ `.env` とは何か、`CSRF_SIGNING_KEY` とは何か

**`.env` の役割**

`.env` は、コンテナに渡す環境変数の値を書いておくファイルです。`compose.yaml` の中の `${POSTGRES_USER}` のような部分は、`docker compose` を実行したときに `.env` の値に置き換わります。DB のパスワードなどの秘密の値をリポジトリに含めないため、`.env` は `.gitignore` により Git の管理対象外になっています。リポジトリには値を書いていない雛形の `.env.example` だけを置き、各自がコピーして作ります。

手順 1 で先に `ls .env` を確認するのは、`cp .env.example .env` が既存の `.env` を**確認なしで上書きする**ためです。すでに作成済みの `.env` を上書きすると、自分で書き込んだ値が消えてしまいます。

**`CSRF_SIGNING_KEY` の役割**

`CSRF_SIGNING_KEY` は、API がログイン前の CSRF トークン（罠サイトからログインさせられる攻撃を防ぐための値）に署名するときに使う秘密鍵です。API は、ブラウザから送られてきたトークンがこの秘密鍵で署名されたものかどうかを確かめ、署名が合わなければログインを受け付けません。決定の経緯は [ADR 0012](adr/0012-session-based-authentication.md) を参照してください。

手順 2 の 2 つのコマンドは、それぞれ次のことを行っています。

| コマンド | 行うこと |
|---|---|
| `grep -q ... \|\| echo ...` | `.env` に `CSRF_SIGNING_KEY=` の行がなければ、空の行を追加する |
| `sed -i '' "s/.../$(openssl rand -hex 32)/" .env` | `openssl rand -hex 32` で推測できないランダムな値（32 バイト = 英数字 64 文字）を作り、`CSRF_SIGNING_KEY=` の行に書き込む |

**Git で管理しない理由**

秘密鍵が漏れると、攻撃者がログイン前の CSRF トークンを自由に作れるようになり、この対策が意味をなさなくなります。そのため、DB のパスワードと同じく `.env` に書き、各自の Mac の中だけに置きます。雛形の `.env.example` には値を書かず、各自がコマンドで作ります。

**値を作り直した場合**

手順 2 のコマンドを再度実行すると、秘密鍵は別の値に変わります。影響を受けるのは、そのときログイン画面を開いていた人のログイン前の CSRF トークンだけで、ログイン画面を開き直せば元どおりログインできます。ログイン済みのセッションは秘密鍵を使っていないため、影響を受けません。

### 手順 3〜5 ─ なぜコンテナを起動する前に Flutter のビルドが必要なのか

ブラウザが `https://myapp.local` を開いたときに受け取るのは、nginx コンテナが配信する HTML・JavaScript などの静的ファイルです。`compose.yaml` では、このファイルの置き場所として `frontend/build/web/` を nginx にマウントしています。

`frontend/build/` は Git の管理対象外のため、clone した直後には存在しません。そのまま起動すると nginx は空のディレクトリを配信することになり、画面が表示されません。そこで、コンテナを起動する前に以下の 3 段階でファイルを用意します。

| 手順 | コマンド | 行うこと |
|---|---|---|
| 手順 3 | `fvm flutter pub get` | `pubspec.yaml` に書かれたパッケージ（Riverpod、go_router など）をダウンロードする |
| 手順 4 | `fvm dart run build_runner build` | `@riverpod` や `@freezed` を付けたクラスから、`*.g.dart` / `*.freezed.dart` のコードを生成する |
| 手順 5 | `fvm flutter build web` | Dart のコードを、ブラウザで動く HTML・JavaScript に変換して `build/web/` に出力する |

**コード生成が必要な理由**

本プロジェクトは、状態管理（Riverpod）やデータクラス（freezed）のコードの一部を、手で書かずに `build_runner` で生成しています。生成されたファイルは Git の管理対象外のため、clone した直後は存在せず、そのままでは手順 5 のビルドが失敗します。コード生成の詳しい使い方は [development-guide.md](development-guide.md) の「コード生成（build_runner）」を参照してください。

**開発中にコードを変更した場合**

`frontend/lib/` を変更した後にブラウザの表示へ反映させるには、手順 4・5 をもう一度実行します。nginx はマウントしたディレクトリをそのまま配信しているため、コンテナの再起動は不要です。

### 手順 7 ─ `docker compose up -d` で何が起動するのか

`compose.yaml` に定義された 4 つのサービスが起動します。

| サービス | 役割 |
|---|---|
| `nginx` | HTTPS の終端、画面（`frontend/build/web/`）の配信、`/api/` へのアクセスの API への転送 |
| `api` | Go の API サーバー。`backend/Dockerfile` でイメージをビルドして起動する |
| `db` | PostgreSQL。データは名前付きボリューム `db-data` に保存され、コンテナを削除しても残る |
| `pgadmin` | ブラウザから DB を確認するためのツール。`http://localhost:5050` で開く |

このほかに、開発環境専用の `compose.override.yaml` により、テスト用 DB を作成してマイグレーションを適用する 2 つのサービス（`db-test-init`・`db-test-migrate`）が 1 回だけ動いて終了します。`docker compose ps` は起動中のコンテナだけを表示するため、この 2 つは一覧に表示されません。

### 手順 8 ─ nginx と API の間はなぜ HTTP なのか

`curl https://myapp.local/api/health` の通信の流れは、[local-https-setup-guide-for-mac.md](local-https-setup-guide-for-mac.md) の「全体像 ─ 何のために何を設定するのか」の図のとおりです。

HTTPS の暗号化が必要なのは、ブラウザから nginx までの通信です。nginx で復号した後、nginx から Go API への転送は Docker 内部のネットワークだけで行われ、外部からは見えません。そのため、API 側は HTTP のまま動かし、証明書の管理を nginx の 1 か所に集約しています。このように、HTTPS の復号を手前のサーバーで引き受ける構成を **HTTPS 終端**と呼びます。

### 手順 9 ─ なぜ開発用 DB にだけ手動でマイグレーションを適用するのか

`docker compose up -d` で起動した直後の開発用 DB には、テーブルが 1 つもありません。API は起動時にマイグレーションを適用しないため、ユーザー一覧やログインのように DB を使う画面は、このままではエラーになります。そこで、手順書 2 でインストールした `migrate` コマンドで、`backend/migrations/` のマイグレーションを適用してテーブルを作ります。

テスト用 DB（`<POSTGRES_DB>_test`）には、`docker compose up -d` のたびに自動で適用されます（手順 7 の解説を参照）。自動で適用されるのはテスト用 DB だけで、開発用 DB にはこの手順のように `migrate` コマンドで適用します。マイグレーションの作り方や戻し方は [development-guide.md](development-guide.md) の「4. DB マイグレーション」を参照してください。

**`set -a; source .env; set +a` は何をしているのか**

| コマンド | 行うこと |
|---|---|
| `set -a` | この後に設定する変数を、自動で環境変数（`export` した状態）にする |
| `source .env` | `.env` に書かれた `POSTGRES_USER=...` などの行を、いま開いているターミナルで実行する |
| `set +a` | `set -a` の設定を元に戻す |

これにより、`.env` の値を書き写さずに `DATABASE_URL` を組み立てられます。読み込んだ値は、そのターミナルを閉じると消えます。

**接続先が `localhost` である理由**

`migrate` コマンドは、コンテナの中ではなく Mac の上で動きます。`compose.yaml` で `db` の 5432 番ポートを Mac の `127.0.0.1:5432` に公開しているため、Mac からは `localhost:5432` で DB に接続できます。一方、API コンテナから DB への接続先は `db:5432` です（`compose.yaml` の `DATABASE_URL`）。同じ DB でも、どこから接続するかによって接続先の書き方が変わります。

**確認に `docker compose exec` を使う理由**

`docker compose exec db ...` は、起動中の `db` コンテナの中でコマンドを実行します。コンテナの中には `.env` の値が環境変数として渡されているため、Mac のターミナルで `.env` を読み込んでいなくても確認できます。`schema_migrations` は、`migrate` が適用済みのマイグレーションの番号を記録するテーブルです。`dirty` が `t` の場合は適用に失敗した状態で、[development-guide.md](development-guide.md) の「失敗したときの復旧手順」に従って復旧します。

### 補足 ─ よくあるエラーと対処

**`curl: (6) Could not resolve host: myapp.local`**

`/etc/hosts` の登録が反映されていません。[local-https-setup-guide-for-mac.md](local-https-setup-guide-for-mac.md) の手順 4 の `grep` で登録内容を確認し、キャッシュのクリアを再度実行してください。

**`curl: (60) SSL certificate problem`、またはブラウザで証明書の警告が表示される**

ローカル認証局が Mac に登録されていません。[local-https-setup-guide-for-mac.md](local-https-setup-guide-for-mac.md) の手順 2 の `mkcert -install` を再度実行してください。Firefox の場合は、同じ手順書の解説にある `brew install nss` も必要です。

**`curl: (7) Failed to connect to myapp.local port 443`**

nginx コンテナが起動していません。以下でコンテナの状態を確認してください。

```bash
docker compose ps
```

nginx が起動していない場合は、以下でエラーの内容を確認します。証明書のファイルが見つからないという内容（`cannot load certificate`）であれば、[local-https-setup-guide-for-mac.md](local-https-setup-guide-for-mac.md) の手順 3 のファイル名と保存場所を確認してください。

```bash
docker compose logs nginx
```

**`docker compose up -d` で `port is already allocated` / `address already in use` と表示される**

コンテナが使うポート（`80`・`443`・`5050`・`5432`）を、Mac 上の別のソフトがすでに使用しています。使用中のプロセスは以下で確認できます（`5432` の部分は、エラーに表示されたポートの番号に置き換えます）。

```bash
lsof -i :5432
```

Homebrew でインストールした PostgreSQL などが表示された場合は、そのソフトを停止してから `docker compose up -d` を再度実行してください。

**`api` の `STATUS` が `Up` にならない、または `Restarting` が続く**

API は、必要な環境変数が 1 つでも設定されていないと起動せずに終了します。以下でエラーの内容を確認してください。`CSRF_SIGNING_KEY` に関するエラーであれば、手順 2 をやり直してから `docker compose up -d` を再度実行します。

```bash
docker compose logs api
```

**ブラウザで開くと、`403 Forbidden` や `404 Not Found` が表示される**

`frontend/build/web/` にビルドの成果物がありません。手順 3〜5 をやり直してください。

**`migrate` で `connection refused` と表示される**

`db` コンテナが起動していません。手順 7 の `docker compose ps` で `db` の状態を確認してください。

**`migrate` で `password authentication failed` と表示される、または接続先の組み立てに失敗する**

`.env` の値がいま開いているターミナルに読み込まれていません。手順 9 の `set -a; source .env; set +a` から実行し直してください。ターミナルを開き直した場合も、読み込み直しが必要です。
