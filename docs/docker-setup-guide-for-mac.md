# Docker / Docker Compose セットアップ手順書（macOS 向け）

本プロジェクトの開発環境（nginx・PostgreSQL・pgAdmin・API サーバーのコンテナ）を動かすために、macOS へ Docker と Docker Compose をインストールする手順です。
Docker を初めて使う方を対象としています。

- 対象 OS: macOS（Apple Silicon / Intel 共通）
- 対象シェル: zsh（macOS の標準シェル）
- インストールするもの: Colima（Docker を動かすための Linux 仮想マシン）、Docker CLI、Docker Compose、Docker Buildx

---

## なぜ Docker Desktop ではなく Colima を使うのか

Mac で Docker を使う方法としては Docker Desktop が有名ですが、本プロジェクトでは **Docker Desktop は使わず、Colima とコマンド（CLI）で Docker を操作します。** 理由は以下の 3 点です。

1. **Docker Desktop は、一定規模以上の組織では有料になるため**
   従業員 250 人以上、または年間収益 1,000 万米ドル以上の企業で業務利用する場合は、有償サブスクリプションの契約が必要です。Colima は MIT ライセンスのオープンソースソフトウェアであり、組織の規模に関係なく無料で利用できます。
2. **コマンドでコンテナを操作するなら、Docker Desktop は不要なため**
   Docker Desktop の主な役割は「Docker を動かす Linux 仮想マシンの用意」と「GUI の提供」です。仮想マシンは Colima で用意でき、コンテナの操作は `docker` / `docker compose` コマンドで行えるため、Docker Desktop がなくても開発に必要なことはすべて行えます。
3. **AI への操作の依頼や、デプロイ時の CI/CD を考えると、コマンドでの操作に慣れておいた方がよいため**
   AI のコーディングエージェントにコンテナを操作させる場合や、GitHub Actions などの CI/CD でビルド・デプロイを自動化する場合は、GUI ではなくコマンドで操作します。普段からコマンドで操作していれば、同じコマンドをそのまま AI への指示や CI/CD の設定に使えます。

---

## 1. 手順

### 手順 0. すでにインストールされているか確認する

以下の 5 つのコマンドを順に実行します。

```bash
colima version
```

```bash
docker --version
```

```bash
docker compose version
```

```bash
docker buildx version
```

```bash
docker info
```

**表示結果による分岐**

上の行から順に当てはまるものを探し、最初に当てはまった行の対応を行ってください。

| 表示結果 | 状態 | 対応 |
|---|---|---|
| 5 つともエラーなく表示される | インストール済み・起動済み | セットアップ不要です |
| `colima version` または `docker --version` で `zsh: command not found` と表示される | Colima または Docker CLI が未インストール | 手順 1 へ進んでください |
| `docker compose version` または `docker buildx version` で `docker: unknown command` と表示される | Compose または Buildx が未導入、または未登録 | 手順 2 へ進んでください |
| 上 4 つは表示されるが `docker info` でエラー | インストール済み・未起動 | 手順 4 へ進んでください |

### 手順 1. Homebrew を用意する

Homebrew があるか確認します。

```bash
brew --version
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| `Homebrew` から始まるバージョンが表示される | インストール済みです。手順 2 へ進んでください |
| `zsh: command not found: brew` と表示される | 未インストールです。下記の「Homebrew をインストールする」を実行してください |

**Homebrew をインストールする**

以下を実行します（[Homebrew 公式サイト](https://brew.sh/ja/) に掲載されているコマンドと同じものです）。

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

途中で macOS の管理者パスワードの入力と、`Press RETURN/ENTER to continue` の表示に対する `Enter` キーの入力を求められます。Xcode コマンドラインツールが入っていない Mac では、そのインストールも自動で行われるため、10 分ほどかかることがあります。

最後に以下のように表示されればインストール完了です。

```
==> Installation successful!
```

**Apple Silicon の Mac では「Next steps」のコマンドを実行する**

インストールの最後に表示される `==> Next steps:` の下に、`brew` コマンドを使えるようにするためのコマンドが表示されます。**表示されたコマンドを、上から順にすべて実行してください。** 多くの場合、以下の 3 つです。

```bash
echo >> ~/.zprofile
```

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
```

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Intel の Mac では「Next steps」にこれらのコマンドは表示されず、実行も不要です。

**インストールできたか確認する**

```bash
brew --version
```

`Homebrew` から始まるバージョンが表示されれば成功です。

### 手順 2. Colima と Docker 関連のコマンドをインストールする

```bash
brew install colima docker docker-compose docker-buildx
```

すでにインストール済みのものがある場合は、その旨が表示されるだけなので問題ありません。

インストール後、`docker` コマンドが使えるか確認します。

```bash
docker --version
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| `Docker version` から始まるバージョンが表示される | 手順 3 へ進んでください |
| `zsh: command not found: docker` と表示される | 下記の「`docker` コマンドが見つからない場合」を実行してください |

**`docker` コマンドが見つからない場合**

以下の 2 つのコマンドを順に実行します。

```bash
brew uninstall docker-completion
```

```bash
brew link docker
```

実行後、もう一度 `docker --version` を実行し、バージョンが表示されることを確認してから手順 3 へ進んでください。

### 手順 3. Docker Compose と Docker Buildx を `docker` コマンドに登録する

Docker の設定ファイル `~/.docker/config.json` があるか確認します。

```bash
cat ~/.docker/config.json
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| `No such file or directory` と表示される | 下記の「ファイルがない場合」を実行してください |
| `{` から始まる内容が表示される | 下記の「ファイルがある場合」を実行してください |

**ファイルがない場合**

以下を実行して、設定ファイルを作成します。

```bash
mkdir -p ~/.docker && cat > ~/.docker/config.json << EOF
{
  "cliPluginsExtraDirs": [
    "$(brew --prefix)/lib/docker/cli-plugins"
  ]
}
EOF
```

**ファイルがある場合**

既存の設定を消さないよう、コマンドで上書きせず、テキストエディタで 1 項目だけ追記します。

```bash
open -e ~/.docker/config.json
```

最初の `{` の直後に、以下の 3 行を追記して保存します（Intel Mac の場合は `/opt/homebrew` を `/usr/local` に置き換えます）。

```json
  "cliPluginsExtraDirs": [
    "/opt/homebrew/lib/docker/cli-plugins"
  ],
```

追記後のファイルは、以下のような形になります（既存の項目は環境によって異なります）。

```json
{
  "cliPluginsExtraDirs": [
    "/opt/homebrew/lib/docker/cli-plugins"
  ],
  "auths": {},
  "currentContext": "colima"
}
```

**登録できたか確認する**

```bash
docker compose version
```

```bash
docker buildx version
```

どちらもバージョンが表示されれば成功です。

### 手順 4. Colima を起動する

Colima が起動しているか確認します。

```bash
colima status
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| `colima is running` と表示される | 起動済みです。手順 5 へ進んでください |
| `colima is not running` と表示される | 下記のコマンドで起動してください |

```bash
colima start
```

初回は Linux 仮想マシンのイメージをダウンロードするため、数分かかります。最後に以下のように `done` と表示されれば起動完了です。

```
INFO[0000] starting colima
...
INFO[0045] done
```

### 手順 5. 起動できたか確認する

```bash
colima status
```

`colima is running` と表示されれば、仮想マシンは起動しています。

```bash
docker info
```

エラーなく設定情報が一覧表示されれば成功です。

### 手順 6. Docker の動作確認をする

```bash
docker run --rm hello-world
```

```
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

上記が表示されれば Docker は正常に動作しています。

### 手順 7. Docker Compose の動作確認をする

作業用の一時ディレクトリを作成し、移動します。

```bash
mkdir -p ~/tmp/compose-test && cd ~/tmp/compose-test
```

確認用の `compose.yaml` を作成します。

```bash
cat > compose.yaml << 'YAML'
services:
  web:
    image: nginx:1.30.4-alpine
    ports:
      - "8080:80"
YAML
```

起動します。

```bash
docker compose up -d
```

ブラウザで [http://localhost:8080](http://localhost:8080) を開き、「Welcome to nginx!」と表示されれば成功です。

以下でも確認できます。

```bash
curl -s http://localhost:8080 | head -5
```

停止して後片付けをします。

```bash
docker compose down
```

```bash
cd ~ && rm -rf ~/tmp/compose-test
```

確認用に取得した nginx イメージも削除する場合は以下を実行します。

```bash
docker image rm nginx:1.30.4-alpine
```

以上でセットアップ完了です。

---

## 2. 各手順の解説

### 手順 0 ─ なぜ 5 つのコマンドを確認するのか

本プロジェクトの Docker 環境は「仮想マシン（Colima）」「コマンド（CLI）」「プラグイン（Compose / Buildx）」「本体（Engine）」に分かれている構成のため、確認すべき点が複数あります。

| コマンド | 何を確認しているか |
|---|---|
| `colima version` | 仮想マシンを動かす Colima が入っているか |
| `docker --version` | 操作用のコマンド（CLI）が入っているか |
| `docker compose version` | Compose 機能が使える状態か |
| `docker buildx version` | Buildx（イメージのビルド機能）が使える状態か |
| `docker info` | 本体（Engine）が**起動している**か |

`colima version` を確認するのは、`docker info` のエラーだけでは「Colima が入っていない」のか「Colima は入っているが起動していない」のかを区別できないためです。

特に重要なのが `docker info` です。`docker --version` はコマンドの存在を確認するだけなので、Colima が起動していなくても表示されます。一方 `docker info` は本体へ問い合わせを行うため、本体が止まっていると以下のようなエラーになります。

```
failed to connect to the docker API at unix:///Users/ユーザー名/.colima/default/docker.sock
```

このエラーは「インストールされていない」のではなく「**起動していない**」という意味です。初心者がつまずきやすい箇所なので、確認段階で切り分けておきます。

### 手順 1 ─ Homebrew とは何か、なぜ「Next steps」が必要なのか

Homebrew は、macOS にコマンドラインのツールをインストールするための**パッケージ管理ツール**です。本プロジェクトで使う Colima・Docker・Go・FVM・mkcert は、いずれも `brew install` でインストールします。インストール・更新・削除の方法がすべてのツールで同じになるため、管理が楽になります。

**Apple Silicon の Mac で「Next steps」が必要な理由**

Homebrew は、Apple Silicon の Mac では `/opt/homebrew` に、Intel の Mac では `/usr/local` にインストールされます。ターミナルは PATH に登録された場所からしかコマンドを探しませんが、`/usr/local/bin` は最初から PATH に入っている一方で、`/opt/homebrew/bin` は入っていません。そのため Apple Silicon の Mac では、PATH に追加しないと `brew` コマンドが見つかりません。

「Next steps」の 3 つのコマンドは、それぞれ次のことを行っています。

| コマンド | 行うこと |
|---|---|
| `echo >> ~/.zprofile` | 設定ファイル `~/.zprofile` の末尾に空行を追加する（既存の内容と区切るため） |
| `echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile` | ターミナルを開くたびに Homebrew の PATH などを設定する 1 行を、`~/.zprofile` に追記する |
| `eval "$(/opt/homebrew/bin/brew shellenv)"` | 上の 1 行の設定を、いま開いているターミナルにも反映させる |

`~/.zprofile` は、ターミナルを開いたとき（ログイン時）に読み込まれる設定ファイルです。ここに書いておくことで、次からはターミナルを開くだけで `brew` コマンドが使えるようになります。

### 手順 2 ─ Colima と各コマンドの役割

**Docker は本来 Linux の技術です。** コンテナは Linux カーネルの機能を使って動くため、macOS 上でそのまま動かすことはできません。

そこで macOS では、内部に軽量な Linux 仮想マシンを立ち上げ、その中で Docker Engine を動かします。Colima はこの仮想マシンを用意するツールです。

```
macOS
 ├─ docker（Docker CLI：ターミナルから操作するコマンド）
 │   ├─ docker compose（Docker Compose：複数コンテナをまとめて扱う機能）
 │   └─ docker buildx（Docker Buildx：イメージをビルドする機能）
 │        ↓ 操作の指示を送る
 └─ Colima
     └─ Linux 仮想マシン
         └─ Docker Engine（コンテナを実際に動かす本体）
```

| インストールするもの | 役割 |
|---|---|
| `colima` | Linux 仮想マシンを起動し、その中で Docker Engine を動かす |
| `docker` | Docker Engine を操作するコマンド（Docker CLI）。Engine 本体は含まない |
| `docker-compose` | `docker compose` コマンドの実体（CLI プラグイン） |
| `docker-buildx` | `docker build` や `docker compose build` でイメージをビルドする機能の実体（CLI プラグイン）。本プロジェクトの API サーバーのようにイメージをビルドするサービスで必要になる |

Docker Desktop は上記一式に GUI を加えて 1 つのアプリにまとめたものです。本プロジェクトでは GUI を使わないため、必要な部品だけを個別にインストールしています。

**インストール後に `docker` コマンドが見つからないことがある理由**

Homebrew は、インストールしたコマンドを `/opt/homebrew/bin`（Intel Mac では `/usr/local/bin`）にシンボリックリンクとして配置します（これを「リンク」と呼びます）。ターミナルはこの場所からコマンドを探すため、リンクがないとインストール済みでも `command not found` になります。

以前に `docker-completion`（Docker コマンドの入力補完だけを提供する、現在は非推奨のパッケージ）をインストールしていた環境では、`docker` と `docker-completion` が同じ補完ファイルを配置しようとして衝突します。Homebrew はリンクを 1 つでも作れないと処理全体を中断するため、`docker` コマンド本体のリンクも作られません。

現在の `docker` パッケージには補完ファイルが含まれているため、`docker-completion` は削除して問題ありません。削除してから `brew link docker` を実行すると、リンクが作成されて `docker` コマンドが使えるようになります。

### 手順 3 ─ なぜ設定ファイルへの登録が必要なのか

`docker compose` や `docker buildx` は、`docker` コマンドに後から機能を追加する**プラグイン**という仕組みで動いています。`docker` コマンドは、決まった場所に置かれたプラグインしか探しません。

Homebrew でインストールしたプラグインは `/opt/homebrew/lib/docker/cli-plugins`（Intel Mac では `/usr/local/lib/docker/cli-plugins`）に置かれますが、ここは `docker` コマンドが既定で探す場所ではありません。そのため、設定ファイル `~/.docker/config.json` の `cliPluginsExtraDirs`（追加でプラグインを探す場所）にこのディレクトリを登録しています。

登録しないと、インストール済みであっても `docker: unknown command: docker compose` というエラーになります。

「ファイルがない場合」のコマンドでは、`$(brew --prefix)` の部分が実行時に Homebrew のインストール先（`/opt/homebrew` または `/usr/local`）に置き換わるため、Apple Silicon / Intel のどちらでもそのまま実行できます。

「ファイルがある場合」にコマンドで作成し直さないのは、既存の設定を消さないためです。Colima は初回起動時に、このファイルへ `"currentContext": "colima"`（`docker` コマンドの接続先を Colima にする設定）を書き込みます。上書きするとこの設定が消え、`docker` コマンドが Colima に接続できなくなります。

### 手順 4 ─ なぜ「起動」という操作が必要なのか

Go や Git のようなコマンドラインツールは、インストールすれば即座に使えます。しかし Docker は、前述の通り**仮想マシンの中で常駐する本体（Docker Engine）**を必要とします。

`colima start` は、Linux 仮想マシンと Docker Engine を起動するコマンドです。Mac を再起動すると仮想マシンも停止するため、Docker を使う前に再度 `colima start` を実行してください。停止する場合は `colima stop` を実行します。

**Mac へのログイン時に自動で起動したい場合**

以下を実行すると、Mac にログインしたときに Colima が自動で起動するようになります。

```bash
brew services start colima
```

**仮想マシンの CPU・メモリを変更したい場合**

`colima start` は、既定では CPU 2 コア・メモリ 2GB の仮想マシンを作成します。コンテナの動作が重い場合は、一度停止してから CPU とメモリを指定して起動し直します。

```bash
colima stop
colima start --cpu 4 --memory 4
```

### 手順 5 ─ `docker compose` と `docker-compose` の違い

古い解説記事では、ハイフン付きの `docker-compose` というコマンドが使われています。これは Compose v1（Python 製の独立したツール）の書き方で、**すでに開発が終了しています**。

現在は Compose が Docker CLI のサブコマンド（プラグイン）として統合され、ハイフンなしの `docker compose` が正式な書き方です。

| 書き方 | 世代 | 現在の扱い |
|---|---|---|
| `docker-compose up`（ハイフンあり） | v1 | 非推奨。開発終了 |
| `docker compose up`（スペース区切り） | v2 以降 | 現行の正式な書き方 |

手順 2 でインストールした Homebrew のパッケージ名は `docker-compose` ですが、中身は現行のプラグイン版です。本プロジェクトではハイフンなしの書き方を使用します。

### 手順 6 ─ `docker run --rm hello-world` は何をしているのか

このコマンドは、Docker の一連の動作をすべて確認できる公式の動作確認用イメージです。実行すると以下が順に行われます。

1. ローカルに `hello-world` イメージがあるか探す
2. 無ければ Docker Hub（イメージの公開リポジトリ）からダウンロードする
3. イメージからコンテナを作成して実行する
4. メッセージを表示して終了する

つまり「ネットワーク接続 → イメージ取得 → コンテナ実行」がすべて通ったことを 1 コマンドで確認できます。

**`--rm` の意味**

コンテナは終了しても、既定では削除されずに残り続けます。`--rm` を付けると終了と同時に自動削除されるため、動作確認のような使い捨ての実行に適しています。

**イメージとコンテナの違い**

初学者が最も混同しやすい概念です。

| 用語 | 位置づけ | たとえ |
|---|---|---|
| イメージ | コンテナの設計図。読み取り専用 | アプリのインストーラ |
| コンテナ | イメージから作られた実行中の実体 | 実際に起動しているアプリ |

1 つのイメージから複数のコンテナを作ることができます。`docker image rm` で消えるのは設計図、`docker rm` で消えるのは実体、という違いがあります。

### 手順 7 ─ Docker Compose は何を解決するのか

`docker run` は**コンテナを 1 つずつ**起動するコマンドです。本プロジェクトのように nginx・PostgreSQL・pgAdmin・API サーバーと複数のコンテナを扱う場合、それぞれに対してポート設定・環境変数・ボリューム・起動順序をコマンドライン引数で指定することになり、現実的ではありません。

Docker Compose は、この構成を `compose.yaml` というファイルに記述しておき、**まとめて起動・停止できるようにする仕組み**です。

| コマンド | 動作 |
|---|---|
| `docker compose up -d` | `compose.yaml` の全サービスを起動する |
| `docker compose down` | 起動したコンテナを停止し、削除する |

`-d`（デタッチモード）を付けるとバックグラウンドで実行され、ターミナルを引き続き操作できます。付けない場合はログが流れ続け、`Ctrl + C` を押すまでターミナルが占有されます。

**動作確認で `ports: "8080:80"` と書いた理由**

コンテナは独立したネットワーク空間で動くため、そのままでは Mac 側のブラウザからアクセスできません。`"8080:80"` は「**Mac の 8080 番ポート**へのアクセスを、**コンテナの 80 番ポート**へ転送する」という設定です。左が Mac 側、右がコンテナ側、と覚えてください。

これにより `http://localhost:8080` で、コンテナ内の nginx（80 番で待ち受け）に到達できます。

### 補足 ─ よくあるエラーと対処

**インストール後も `zsh: command not found: docker` と表示される**

`docker` はインストールされていますが、`docker-completion` との衝突でリンクが作られていません。`brew uninstall docker-completion` を実行してから `brew link docker` を実行してください（手順 2 の解説を参照）。

**`failed to connect to the docker API` / `Cannot connect to the Docker daemon`**

Colima が起動していません。`colima start` を実行し、`done` と表示されてから再実行してください。

**`docker: unknown command: docker compose`**

Docker Compose が `docker` コマンドに登録されていません。手順 3 の `~/.docker/config.json` の内容を確認してください。

**`compose build requires buildx` と表示される**

Docker Buildx がインストールされていないか、登録されていません。`brew install docker-buildx` を実行し、手順 3 の登録内容を確認してください。

**`port is already allocated`**

指定したポートを別のプロセスがすでに使用しています。使用中のプロセスは以下で確認できます。

```bash
lsof -i :8080
```

該当プロセスを終了するか、`compose.yaml` の左側の番号を別の値（`"8081:80"` など）に変更してください。
