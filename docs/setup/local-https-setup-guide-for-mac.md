# ローカル HTTPS / カスタムドメイン セットアップ手順書（macOS 向け）

本プロジェクトの開発環境に `https://myapp.local` でアクセスできるようにするため、ローカル用の証明書を作成し、カスタムドメインを Mac に登録する手順です。
HTTPS や証明書を初めて扱う方を対象としています。

- 対象 OS: macOS（Apple Silicon / Intel 共通）
- 対象シェル: zsh（macOS の標準シェル）
- インストールするもの: mkcert（ローカル開発用の証明書作成ツール）

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

ローカル認証局がすでに登録されているか確認します。

```bash
security find-certificate -c mkcert /Library/Keychains/System.keychain
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| `keychain: "/Library/Keychains/System.keychain"` から始まる情報が表示される | 登録済みです。手順 3 へ進んでください |
| `The specified item could not be found in the keychain.` を含むエラーが表示される | 下記のコマンドで登録してください |

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

以上でセットアップ完了です。証明書とドメインが実際に使えるかどうかは、[app-launch-guide-for-mac.md](app-launch-guide-for-mac.md) でアプリを起動して確認します。

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
