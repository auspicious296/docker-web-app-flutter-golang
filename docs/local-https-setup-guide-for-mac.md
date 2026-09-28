# ローカル HTTPS / カスタムドメイン セットアップ手順書（macOS 向け）

本プロジェクトの開発環境に `https://myapp.local` でアクセスできるようにするため、ローカル用の証明書を作成し、カスタムドメインを Mac に登録する手順です。
HTTPS や証明書を初めて扱う方を対象としています。

- 対象 OS: macOS（Apple Silicon / Intel 共通）
- 対象シェル: zsh（macOS の標準シェル）
- インストールするもの: mkcert（ローカル開発用の証明書作成ツール）
- 前提: [docker-setup-guide-for-mac.md](docker-setup-guide-for-mac.md) の手順が完了していること

以降のコマンドは、特に記載がない限り**プロジェクトのルートディレクトリ**で実行します。

---

## 1. 手順

### 手順 0. すでにインストールされているか確認する

```bash
mkcert -version
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| `v1.4.4` のようにバージョンが表示される | インストール済みです。手順 2 へ進んでください |
| `zsh: command not found: mkcert` と表示される | 未インストールです。手順 1 へ進んでください |

### 手順 1. mkcert をインストールする

```bash
brew install mkcert
```

### 手順 2. ローカル認証局を Mac に登録する

```bash
mkcert -install
```

macOS の管理者パスワードの入力を求められます。

```
The local CA is now installed in the system trust store! ⚡️
```

上記のように表示されれば成功です。この操作は Mac 1 台につき 1 回だけ行います。

### 手順 3. 証明書を作成する

```bash
mkcert \
  -cert-file docker-containers/nginx/certs/myapp.local.pem \
  -key-file docker-containers/nginx/certs/myapp.local-key.pem \
  myapp.local
```

作成されたか確認します。

```bash
ls docker-containers/nginx/certs/
```

```
myapp.local-key.pem  myapp.local.pem
```

上記の 2 ファイルが表示されれば成功です。

### 手順 4. カスタムドメインを登録する

`/etc/hosts` に `myapp.local` を追記します。管理者パスワードの入力を求められます。

```bash
sudo sh -c 'printf "127.0.0.1 myapp.local\n::1 myapp.local\n" >> /etc/hosts'
```

追記されたか確認します。

```bash
grep myapp.local /etc/hosts
```

```
127.0.0.1 myapp.local
::1 myapp.local
```

上記の 2 行が表示されれば成功です。

Mac が保持している名前解決のキャッシュをクリアします。

```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

### 手順 5. 動作確認する

環境変数のファイル `.env` がまだない場合は、雛形からコピーして作成し、CSRF 対策の署名に使う秘密鍵（`CSRF_SIGNING_KEY`）を書き込みます。

```bash
cp .env.example .env
grep -q '^CSRF_SIGNING_KEY=' .env || echo 'CSRF_SIGNING_KEY=' >> .env
sed -i '' "s/^CSRF_SIGNING_KEY=.*/CSRF_SIGNING_KEY=$(openssl rand -hex 32)/" .env
```

秘密鍵が書き込まれたことを確認します。

```bash
grep '^CSRF_SIGNING_KEY=' .env
```

`CSRF_SIGNING_KEY=` の後ろに 64 文字の英数字が続いていれば成功です。値は人によって異なります。

Colima が起動していない場合は、先に起動します。

```bash
colima start
```

コンテナを起動します。

```bash
docker compose up -d
```

API にアクセスします。

```bash
curl https://myapp.local/api/health
```

```
{"status":"ok"}
```

上記が表示されればセットアップ完了です。証明書の警告が出ず、`https://myapp.local` の nginx を経由して Go API に到達できています。

---

## 2. 各手順の解説

### 全体像 ─ 何のために何を設定するのか

ブラウザや `curl` から `https://myapp.local/api/health` にアクセスしたとき、裏では以下の流れで処理されます。

```
ブラウザ
   │ ① myapp.local はどこ？ → /etc/hosts により 127.0.0.1（自分の Mac）
   ↓
nginx コンテナ（443 番）
   │ ② HTTPS 通信を証明書で復号する（HTTPS 終端）
   │ ③ パスが /api/ で始まるので API へ転送する
   ↓
Go API コンテナ（8080 番、HTTP）
```

| 手順 | 対応する処理 |
|---|---|
| 手順 4（`/etc/hosts`） | ① ドメイン名を自分の Mac に向ける |
| 手順 2・3（mkcert） | ② nginx が使う証明書を用意する |
| リポジトリの設定ファイル | ③ nginx の転送設定。各自の作業は不要です |

### 手順 1〜3 ─ なぜ mkcert を使うのか

HTTPS 通信には「このサーバーは本物の `myapp.local` である」ことを証明する**証明書**が必要です。通常の Web サイトでは、世界中のブラウザが信頼している認証局（CA）が証明書を発行します。しかし `myapp.local` は自分の Mac の中にしか存在しないドメインのため、正規の認証局からは証明書を発行してもらえません。

自分で証明書を作ること（自己署名証明書）もできますが、ブラウザはそれを信頼しないため、アクセスするたびに「この接続ではプライバシーが保護されません」という警告が表示されます。

mkcert はこの問題を以下の 2 段階で解決します。

| 手順 | 行うこと |
|---|---|
| 手順 2（`mkcert -install`） | 自分の Mac 専用の認証局を作り、macOS の「信頼する認証局」の一覧に登録する |
| 手順 3（`mkcert myapp.local`） | その認証局を使って `myapp.local` 用の証明書を発行する |

Mac が認証局を信頼しているため、その認証局が発行した証明書もブラウザに信頼され、警告なしで HTTPS 接続できます。

なお、Firefox は macOS とは別に独自の信頼リストを持っています。Firefox を使う場合は、手順 2 の前に `brew install nss` を実行してください。

### 手順 3 ─ 作成されるファイルと、Git で管理しない理由

| ファイル | 中身 | nginx 内での配置先 |
|---|---|---|
| `myapp.local.pem` | 証明書（公開してよい情報） | `/etc/nginx/certs/myapp.local.pem` |
| `myapp.local-key.pem` | 秘密鍵（他人に渡してはいけない情報） | `/etc/nginx/certs/myapp.local-key.pem` |

`compose.yaml` で `docker-containers/nginx/certs/` を nginx コンテナの `/etc/nginx/certs/` にマウントしており、nginx の設定ファイル（`docker-containers/nginx/conf.d/default.conf`）がこの 2 ファイルを読み込みます。ファイル名を変えると nginx が起動できなくなるため、手順 3 のコマンドどおりの名前で作成してください。

この 2 ファイルは `.gitignore` の `*.pem` により Git の管理対象外になっています。理由は以下の通りです。

- 証明書は**各自の Mac の認証局**で発行したものであり、他のメンバーの Mac では信頼されない
- 秘密鍵をリポジトリに含めると、誰でも取得できる状態になってしまう

このため、証明書はメンバーごとに各自の Mac で作成します。

### 手順 4 ─ `/etc/hosts` とは何か

`/etc/hosts` は「ドメイン名と IP アドレスの対応表」を書いておくファイルです。Mac はドメイン名にアクセスするとき、インターネット上の DNS に問い合わせる前にこのファイルを確認します。

`127.0.0.1` は「自分自身の Mac」を指す特別な IP アドレスです。`127.0.0.1 myapp.local` と書くことで、`myapp.local` へのアクセスが自分の Mac（で動いている nginx コンテナ）に届くようになります。

**なぜ `::1` の行も追記するのか**

`::1` は `127.0.0.1` の IPv6 版です。macOS は `.local` で終わるドメインを、同じネットワーク上の機器を探す仕組み（Bonjour）でも検索しようとします。IPv4 の行だけを書いた場合、IPv6 のアドレスを Bonjour で探しに行き、その応答を待つためにアクセスのたびに数秒待たされることがあります。`::1` の行も書いておくと、この待ち時間が発生しなくなります。

**キャッシュをクリアする理由**

macOS は一度調べた名前解決の結果をしばらく記憶しています。`/etc/hosts` を書き換えても、古い結果が残っていると反映されないため、手順 4 の最後でキャッシュをクリアしています。

### 手順 5 ─ `CSRF_SIGNING_KEY` とは何か、Git で管理しない理由

`CSRF_SIGNING_KEY` は、API がログイン前の CSRF トークン（罠サイトからログインさせられる攻撃を防ぐための値）に署名するときに使う秘密鍵です。API は、ブラウザから送られてきたトークンがこの秘密鍵で署名されたものかどうかを確かめ、署名が合わなければログインを受け付けません。決定の経緯は [ADR 0012](adr/0012-session-based-authentication.md) を参照してください。

手順 5 の 3 つのコマンドは、それぞれ次のことを行っています。

| コマンド | 行うこと |
|---|---|
| `cp .env.example .env` | 雛形をコピーして `.env` を作る |
| `grep -q ... \|\| echo ...` | `.env` に `CSRF_SIGNING_KEY=` の行がなければ、空の行を追加する |
| `sed -i '' "s/.../$(openssl rand -hex 32)/" .env` | `openssl rand -hex 32` で推測できないランダムな値（32 バイト = 英数字 64 文字）を作り、`CSRF_SIGNING_KEY=` の行に書き込む |

**Git で管理しない理由**

秘密鍵が漏れると、攻撃者がログイン前の CSRF トークンを自由に作れるようになり、この対策が意味をなさなくなります。`.env` は `.gitignore` により Git の管理対象外になっているため、DB のパスワードと同じく、各自の Mac の中だけに置かれます。雛形の `.env.example` には値を書かず、各自がコマンドで作ります。

**値を作り直した場合**

手順 5 のコマンドを再度実行すると、秘密鍵は別の値に変わります。影響を受けるのは、そのときログイン画面を開いていた人のログイン前の CSRF トークンだけで、ログイン画面を開き直せば元どおりログインできます。ログイン済みのセッションは秘密鍵を使っていないため、影響を受けません。

### 手順 5 ─ nginx と API の間はなぜ HTTP なのか

HTTPS の暗号化が必要なのは、ブラウザから nginx までの通信です。nginx で復号した後、nginx から Go API への転送は Docker 内部のネットワークだけで行われ、外部からは見えません。そのため、API 側は HTTP のまま動かし、証明書の管理を nginx の 1 か所に集約しています。このように、HTTPS の復号を手前のサーバーで引き受ける構成を **HTTPS 終端**と呼びます。

### 補足 ─ よくあるエラーと対処

**`curl: (6) Could not resolve host: myapp.local`**

`/etc/hosts` の登録が反映されていません。手順 4 の `grep` で登録内容を確認し、キャッシュのクリアを再度実行してください。

**`curl: (60) SSL certificate problem`、またはブラウザで証明書の警告が表示される**

ローカル認証局が Mac に登録されていません。手順 2 の `mkcert -install` を再度実行してください。

**`curl: (7) Failed to connect to myapp.local port 443`**

nginx コンテナが起動していません。以下でコンテナの状態を確認してください。

```bash
docker compose ps
```

nginx が起動していない場合は、以下でエラーの内容を確認します。証明書のファイルが見つからないという内容（`cannot load certificate`）であれば、手順 3 のファイル名と保存場所を確認してください。

```bash
docker compose logs nginx
```
