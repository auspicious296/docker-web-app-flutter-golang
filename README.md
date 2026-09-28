# docker-web-app-flutter-golang
Flutter（フロントエンド）と GO（バックエンド API）を連携させるフWebアプリケーションの開発コンテナ構築テンプレートです。

## 1. 目的

- Docker Compose を利用して Nginx, PostgreSQL をコンテナ化し、ローカル環境で HTTPS / カスタムドメイン接続（`https://myapp.local`）による開発環境を構築します。
- フロントエンドのアプリケーションはFlutterで開発し、PostgreSQLのデータベースに対してCRUD（create, read, update, delete）の基本的な処理が行えるサンプルプログラムを開発します。
- フロントエンドのFlutterはMVVMのアーキテクチャで構成、管理されています。
- PostgreSQLのデータベースのデータを簡単に確認できるようにpgadminのコンテナも設置します。


## 2. ドキュメント

`docs/` ディレクトリに以下のドキュメントを格納しています。

### 開発の進め方

- [development-guide.md](docs/development-guide.md) — 開発時の作業フローの全体像。どこにコードを書き、どのコマンドでビルドし、成果物がどこへ出力されるのかをまとめています。**アサイン時に最初に読むドキュメントです。**
- [useful-commands.md](docs/useful-commands.md) — 開発時によく使うコマンド集。Docker / Docker Compose / Go / Flutter の起動・停止・ビルドなどのコマンドを用途別にまとめています。

### 開発環境のセットアップ手順（macOS 向け）

プロジェクトにアサインされたら、以下の番号順に手順書に従って開発環境の設定を行ってください。

いずれも初めて触る方を対象に、手順を先に簡潔に記載し、その後に「なぜその操作が必要なのか」の解説を付けた構成になっています。

1〜3 は互いに依存しないため、順不同で実施して構いません。4 は最後の動作確認でコンテナを起動するため、必ず 1（Docker）の完了後に実施してください。

1. [docker-setup-guide-for-mac.md](docs/docker-setup-guide-for-mac.md) — Colima を利用した Docker / Docker Compose のインストール手順（Docker Desktop は使用しません）。
2. [golang-setup-guide-for-mac.md](docs/golang-setup-guide-for-mac.md) — Go のインストール手順。
3. [flutter-setup-guide-for-mac.md](docs/flutter-setup-guide-for-mac.md) — FVM および Flutter SDK のインストール手順。
4. [local-https-setup-guide-for-mac.md](docs/local-https-setup-guide-for-mac.md) — ローカル HTTPS 用の証明書の作成と、カスタムドメイン（`myapp.local`）を `/etc/hosts` に登録する手順。

### 設計判断の記録

- [docs/adr/](docs/adr/) — ADR（Architecture Decision Record）を格納するディレクトリです。アーキテクチャや技術選定に関する決定を、その背景・検討した選択肢・決定理由とあわせて 1 件 1 ファイルで記録します。`grill-with-docs` スキルで作成したものをここに配置します。

### 開発中の進捗・メモ（Git 管理外）

- `docs/etc/` — 開発中の進捗やメモなどを置くディレクトリです。各自の手元だけで使うものであり、`.gitignore` により Git の追跡から除外しています。リポジトリを clone しても、このディレクトリの中身は含まれません。

## 3. 技術スタック

バージョンは 2026 年 9 月時点の最新版を基準に選定しています。

| 区分 | 技術 | バージョン | 用途 |
|---|---|---|---|
| フロントエンド | Flutter（Web ビルド） | 3.47.4（Dart 3.13.3） | MVVM 構成のフロントエンドアプリケーション |
| バックエンド | Go | 1.27.1 | REST API サーバー |
| Web サーバー | nginx | 1.30.4（stable） | 静的ファイル配信、リバースプロキシ、HTTPS 終端 |
| データベース | PostgreSQL | 18.6 | アプリケーションデータの永続化 |
| DB マイグレーション | golang-migrate | 4.20.1 | DB スキーマのマイグレーション管理 |
| DB 管理ツール | pgAdmin 4 | 9.17 | ブラウザからのデータベース確認・操作 |
| 実行基盤 | Colima | 0.10.3 | Docker Engine を動かす Linux 仮想マシン（Docker Desktop は使用しない） |
| 実行基盤 | Docker CLI / Docker Compose / Docker Buildx | 29.8.1 / 5.5.1 / 0.37.1 | コンテナの操作、複数コンテナの管理、イメージのビルド |

フロントエンド（Flutter）で利用する主なパッケージは以下の通りです。選定の理由は [docs/adr/0001-frontend-state-management-and-codegen.md](docs/adr/0001-frontend-state-management-and-codegen.md)（状態管理・画面遷移・コード生成）と [docs/adr/0006-frontend-data-table-package.md](docs/adr/0006-frontend-data-table-package.md)（テーブル表示）に記録しています。

| パッケージ | バージョン | 用途 |
|---|---|---|
| hooks_riverpod | 3.4.3 | 状態管理と依存性注入 |
| flutter_hooks | 0.21.3 | 入力欄の状態（`useTextEditingController` / `useFocusNode` / `useState`）。hooks_riverpod が同梱しているが、直接 import する側として直接依存にも記載している |
| riverpod_annotation / riverpod_generator | 4.0.7 / 4.0.9 | provider をコード生成で定義する |
| go_router | 18.0.1 | 画面遷移。Flutter Web ではパスがそのままブラウザの URL になる |
| freezed / freezed_annotation | 4.0.2 / 3.1.0 | 不変データクラスと sealed class（画面の状態表現） |
| json_serializable / json_annotation | 6.14.1 / 4.12.0 | API レスポンス（DTO）の JSON 変換 |
| http | 1.6.0 | バックエンド API の呼び出し |
| data_table_2 | 2.8.0（**改変版をリポジトリ内に同梱**） | ユーザー一覧のテーブル表示。標準の `DataTable` にヘッダー行と左端列の固定を足したもの。pub.dev からは取得せず、`frontend/packages/data_table_2/` に取り込んだ改変版を使う。**改変の理由と代償は [ADR 0007](docs/adr/0007-vendoring-data-table-2.md)、3.x を採用しない理由は [ADR 0006](docs/adr/0006-frontend-data-table-package.md) を参照** |
| build_runner | 2.16.1 | 上記のコード生成を実行する |

**コード生成を利用しているため、`lib/` を変更したら `build_runner` の実行が必要です。**生成ファイル（`*.g.dart` / `*.freezed.dart`）は Git 管理外のため、リポジトリを clone した直後もビルド前に実行してください。手順は [development-guide.md](docs/development-guide.md) を参照してください。

利用する Docker イメージのタグは以下の通りです。

| サービス | イメージタグ |
|---|---|
| nginx | `nginx:1.30.4-alpine` |
| PostgreSQL | `postgres:18.6-alpine` |
| pgAdmin 4 | `dpage/pgadmin4:9.17` |
| Go（ビルドステージ） | `golang:1.27.1-alpine` |
| Go（実行ステージ） | `alpine:3.24.2` |

### コンテナが利用するポート

ホスト（各自の Mac）に公開するポートは以下の通りです。いずれも `127.0.0.1` に限定して公開しているため、同じネットワーク上の他の PC からは接続できません。

| サービス | ホスト側のポート | アクセス方法・用途 |
|---|---|---|
| nginx | `80` / `443` | `https://myapp.local` でアクセスします。`/api/` 配下へのアクセスは Go API へ転送します。`80`（HTTP）へのアクセスは `443`（HTTPS）へ転送します |
| pgAdmin 4 | `5050` | `http://localhost:5050` でブラウザから開きます |
| PostgreSQL | `5432` | ホストの `migrate` コマンドや DB クライアントから接続します |
| Go API | 公開しない | nginx を経由してのみアクセスします |

Mac 上で同じポートを使用しているソフト（Homebrew でインストールした PostgreSQL など）が起動していると、コンテナが起動できません。その場合は、該当するソフトを停止してからコンテナを起動してください。

### バージョン選定の方針

- **nginx** — 公式は mainline（1.31 系）の利用を推奨していますが、開発環境の安定性を優先し stable 系列の 1.30.4 を採用します。
- **Go** — 最新の 1.27.1 を採用します。Go は「Go 1 互換性保証」により後方互換性が強く維持されるため、古い系列をあえて選ぶ利点がなく、サポート期間も最も長く残ります。
- **PostgreSQL** — 最新のメジャーバージョンである 18 系の最新パッチ 18.6 を採用します。

## 4. プロジェクト内のディレクトリ構成

アプリのソースコードはアプリ単位のフォルダに置き、そのアプリの `Dockerfile` もソースと同じ階層に配置します。全サービスのコンテナ定義はルートの `compose.yaml` にまとめ、開発環境だけで使う定義（テスト用 DB の作成とマイグレーションの適用）は `compose.override.yaml` に分けます（本番では読み込ませません。[開発ガイド](docs/development-guide.md)の「5. デプロイ」を参照）。`docker-containers/` には既製イメージ（nginx / postgres / pgadmin）のコンテナに渡す設定ファイルや証明書を置きます。ビルドが必要な自作アプリ（Flutter / Go）とは分離しています。

```
docker-web-app-flutter-golang/
├── docker-containers/            # 既製イメージのコンテナに渡す設定ファイル
│   ├── nginx/
│   │   ├── conf.d/default.conf   #   nginx の設定（HTTPS 終端、/api/ の転送、ログイン API の呼び出し回数の制限）
│   │   └── certs/                #   mkcert で作成した証明書（Git 管理外）
│   └── postgre-sql+admin/
├── docs/                         # セットアップ手順などのドキュメント
│   └── etc/                      #   開発中の進捗やメモ（Git 管理外）
├── frontend/                     # Flutter アプリ（フロントエンド）
├── backend/                      # Go アプリ（バックエンド API）
├── compose.yaml                  # 全サービスを定義する Docker Compose 定義
├── compose.override.yaml         # 開発環境専用の定義（テスト用 DB の作成とマイグレーションの適用）
└── .env.example                  # 環境変数の雛形（コピーして .env を作成する。.env は Git 管理外）
```

### 4-1. frontend（Flutter / MVVM）

Flutter 公式の App Architecture ガイド（MVVM）に準拠した構成です。依存の向きは `View → ViewModel → Repository → Service` の一方向に固定し、View には状態を持たせず、状態と画面ロジックは ViewModel に集約します。各層のインスタンスは Riverpod の provider を経由して受け渡しますが、依存の向きは変わりません。

```
frontend/
├── Dockerfile                    # マルチステージビルド用
├── pubspec.yaml
├── lib/
│   ├── main.dart                 # エントリポイント（ProviderScope + MaterialApp.router）
│   ├── config/                   # 環境設定
│   │   └── api_config.dart       #   API のベース URL
│   ├── routing/                  # ルーティング定義
│   │   └── router.dart           #   go_router のルート定義
│   ├── ui/                       # View + ViewModel 層
│   │   ├── core/                 #   共通ウィジェット・テーマ
│   │   ├── home/                 #   機能単位のディレクトリ（ホーム画面）
│   │   │   └── view/             #     home_screen.dart（状態を持たないため ViewModel なし）
│   │   ├── health/               #   機能単位のディレクトリ（API 疎通テスト画面）
│   │   │   ├── view/             #     health_screen.dart（View）
│   │   │   └── view_model/       #     health_view_model.dart（ViewModel、画面の状態）
│   │   ├── auth/                 #   機能単位のディレクトリ（ログイン画面）
│   │   └── my_page/              #   機能単位のディレクトリ（マイページ・パスワード変更画面）
│   ├── domain/
│   │   └── models/               # Model（アプリ内のドメインモデル・失敗の種類）
│   └── data/                     # Model の供給元
│       ├── repositories/         #   ViewModel が依存する窓口
│       ├── services/             #   バックエンド API を呼び出すクライアント
│       └── model/                #   API レスポンスの DTO
├── packages/                     # 取り込んだ外部パッケージ（pub.dev から取得しないもの）
│   └── data_table_2/             #   改変版の data_table_2（ADR 0007）
├── test/                         # テスト（ViewModel 単位）
├── web/                          # index.html などのテンプレート
└── build/                        # ビルド成果物（Git 管理外）
```

エンドポイントのパス（`/api/health` など）は、それを呼び出す `data/services/` のクライアントが持ちます。`config/` に置くのは環境によって変わる値（ベース URL）だけです。

ビルド成果物は `flutter build web` により `frontend/build/web/` へ出力されます。開発時はこのディレクトリを nginx コンテナへバインドマウントし、本番相当のビルドでは `frontend/Dockerfile` のマルチステージ構成でビルドした成果物を nginx イメージの `/usr/share/nginx/html` へ `COPY` します。

### 4-2. backend（Go）

Standard Go Project Layout に準拠した構成です。実行可能なパッケージは `cmd/` 配下のみに置き、実装本体は外部から import できない `internal/` に配置します。

```
backend/
├── Dockerfile                    # マルチステージビルド用
├── go.mod
├── go.sum
├── cmd/
│   └── api/
│       └── main.go               # エントリポイント
├── internal/                     # 実装本体（外部から import 不可）
│   ├── config/                   #   環境変数の読み込み
│   ├── handler/                  #   HTTP ハンドラ
│   ├── service/                  #   ビジネスロジック
│   ├── repository/               #   PostgreSQL アクセス
│   └── model/                    #   ドメイン構造体
├── migrations/                   # DB スキーマのマイグレーション
└── bin/                          # ビルド成果物（Git 管理外）
```

ローカルでのビルド成果物は `go build -o ./bin/api ./cmd/api` により `backend/bin/` へ出力します。コンテナ内では `golang` イメージ上でビルドした実行ファイルを、最終ステージの軽量イメージ（alpine / scratch）へ `COPY` します。
