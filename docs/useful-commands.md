# 開発する時によく使うコマンド集

## ◼︎　Colimaのコマンド

Docker のコマンドを使う前に、Colima（Docker Engine を動かす Linux 仮想マシン）が起動している必要がある。

- `colima start`
  - 仮想マシンと Docker Engine を起動する。**Mac の再起動後、Docker を使う前にまず実行する**。
- `colima status`
  - 仮想マシンが起動しているか確認する。起動中なら `colima is running` と表示される。
- `colima stop`
  - 仮想マシンを停止する。停止中は `docker` コマンドが使えない。

## ◼︎　Dockerのコマンド

- `docker container ls`
  - **起動中**のコンテナだけを一覧表示する。
- `docker container ls -a`
  - 停止中のものも含めて**すべて**のコンテナを一覧表示する。起動に失敗したコンテナを探すときに使う。

## ◼︎　Docker composeのコマンド

### ビルド

- `docker compose build`
  - `compose.yaml` の `build:` を持つサービスのイメージを作る。キャッシュを再利用するため 2 回目以降は速い。
- `docker compose build --no-cache`
  - キャッシュを一切使わずイメージを作り直す。`Dockerfile` を変更したのに反映されないときに使う。

### 起動

- `docker compose up -d`
  - **普段の起動はこれ**。イメージの取得・コンテナの作成・起動をまとめて行う。
- `docker compose up -d --build`
  - 起動前にイメージをビルドし直す。`Dockerfile` や依存関係を変更した後の起動に使う。
- `docker compose start`
  - `stop` で止めた**既存のコンテナ**を再開する。コンテナを新規作成しないため、`up` より速い。
    （`start` は `-d` を受け付けない。もともとバックグラウンドで動作する）
- `docker compose run -d`
  - 指定したサービスで**使い捨てのコンテナ**を 1 つ起動し、単発のコマンドを実行する。
    マイグレーションの実行など、通常の起動とは別の処理を流すときに使う。

「-d」はデタッチモード。ターミナルのバックグラウンドで実行される。付けない場合はログが流れ続け、`Ctrl + C` を押すまでターミナルが占有される。

### 停止

- `docker compose stop`
  - コンテナを**停止するだけ**。コンテナ自体は残るので `start` で再開できる。
- `docker compose rm`
  - **停止済み**のコンテナを削除する。起動中のものは削除されない。
- `docker compose rm -s`
  - 起動中のコンテナを停止してから削除する（`-s` は stop の意味）。

### 終了・片付け

- `docker compose down`
  - コンテナとネットワークを停止・削除する。**作業終了時はこれ**。名前付きボリューム（DB のデータなど）は残る。
- `docker compose down --rmi all`
  - 上記に加えて、使用していたイメージも削除する。ディスクを空けたいときや、完全に作り直したいときに使う。

## ◼︎　GOのコマンド

※ `backend/` ディレクトリで実行する。

### 実行・ビルド

- `go run ./cmd/api`
  - ビルドと実行を一度に行う。実行ファイルは残らない。**開発中の動作確認はこれ**。
- `go build -o ./bin/api ./cmd/api`
  - 実行ファイルを `bin/api` として出力する。配布・デプロイ用の成果物を作るときに使う。
- `go build ./...`
  - 成果物を作らず、全パッケージがコンパイルできるかだけを確認する。`./...` は「配下の全パッケージ」の意味。

### 依存関係

- `go mod tidy`
  - `go.mod` を実際のコードに合わせて整える。使っていない依存を削除し、足りない依存を追加する。**import を増減させたら実行する**。
- `go mod download`
  - `go.mod` に書かれた依存をダウンロードする。リポジトリを取得した直後に使う。
- `go get github.com/xxx/yyy`
  - 依存パッケージを追加、または指定して更新する。

### テスト・検査

- `go test ./...`
  - 全パッケージのテストを実行する。
- `go test -v ./internal/service`
  - 指定したパッケージのテストだけを、1 件ずつ詳細表示で実行する。
- `go test -cover ./...`
  - テストがコードのどれだけを通っているか（カバレッジ）を表示する。
- `go vet ./...`
  - コンパイルは通るが間違いである可能性が高い書き方を検出する静的解析。
- `gofmt -l .`
  - 整形されていないファイルを一覧表示する（`-l` は list の意味。書き換えはしない）。
- `gofmt -w .`
  - ソースコードを標準の書式に整形して上書きする。

### 片付け

- `go clean -cache`
  - ビルドキャッシュを削除する。ビルド結果がおかしいときに使う。


## ◼︎　Flutterのコマンド

※ `frontend/` ディレクトリで実行する。FVM 利用のため、コマンドの先頭に `fvm` を付ける。

### 実行

- `fvm flutter run -d chrome`
  - Chrome を起動して開発実行する。**開発中の動作確認はこれ**。
- `fvm flutter devices`
  - 実行先として使えるデバイスを一覧表示する。`Chrome (web)` が出ていれば Web 実行が可能。

`fvm flutter run` 中に使えるキー操作

| キー | 動作 |
|---|---|
| `r` | ホットリロード。変更を画面に即反映する（画面の状態は保持される） |
| `R` | ホットリスタート。アプリを再起動する（状態は初期化される） |
| `q` | 実行を終了する |

### ビルド

- `fvm flutter build web`
  - `build/web/` へ配信用の静的ファイル一式を出力する。既定でリリースビルド（最適化あり）になる。
- `fvm flutter build web --no-tree-shake-icons`
  - アイコンの未使用分を削る処理を無効にする。アイコンが表示されないエラーが出たときに使う。

### 依存関係

- `fvm flutter pub get`
  - `pubspec.yaml` に書かれたパッケージを取得する。リポジトリを取得した直後や、`pubspec.yaml` を変更した後に実行する。
- `fvm flutter pub add パッケージ名`
  - パッケージを追加する。`pubspec.yaml` への追記と取得を同時に行う。
- `fvm flutter pub outdated`
  - 新しいバージョンが出ているパッケージを一覧表示する。
- `fvm flutter pub upgrade`
  - パッケージを更新可能な範囲で最新化する。

### 検査・テスト・整形

- `fvm flutter analyze`
  - 静的解析。型の誤りや未使用の変数などを検出する。**コミット前に実行する**。
- `fvm flutter test`
  - テストを実行する。
- `fvm dart format lib`
  - `lib/` 配下のソースコードを標準の書式に整形する。

### 片付け

- `fvm flutter clean`
  - `build/` と中間ファイルを削除する。ビルドが通らない、変更が反映されないときに使う。実行後は `fvm flutter pub get` が必要。
