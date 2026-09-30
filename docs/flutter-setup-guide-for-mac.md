# Flutter セットアップ手順書（macOS 向け / FVM 利用）

本プロジェクトのフロントエンドを開発するために、macOS へ FVM（Flutter Version Management）と Flutter SDK をインストールする手順です。
Flutter を初めて使う方を対象としています。

- 対象 OS: macOS（Apple Silicon / Intel 共通）
- 対象シェル: zsh（macOS の標準シェル）
- インストールするもの: FVM 4.3.1 / Flutter SDK 3.47.4（Dart 3.13.3）
- ビルド対象: Web のみ（**Xcode 本体・Android Studio は不要です**）

---

## 1. 手順

### 手順 0. すでにインストールされているか確認する

以下の 2 つのコマンドを順に実行します。

```bash
fvm --version
```

```bash
fvm list
```

**`fvm --version` の結果による分岐**

| 表示結果 | 状態 | 対応 |
|---|---|---|
| `4.3.1` と表示される | FVM は最新です | 手順 1 を実施した後、FVM のインストール（手順 2・3）は飛ばし、下記の `fvm list` の結果に従って進んでください |
| `4.3.1` より古いバージョンが表示される | 更新が必要です | 下記「FVM の更新」を実行後、手順 1 へ |
| `zsh: command not found: fvm` | 未インストールです | 手順 1 へ |

**FVM の更新**

```bash
brew upgrade fvm
```

Homebrew 以外の方法で導入した FVM の場合は上記コマンドが使えません。その際は一度削除してから、手順 3 で入れ直してください。

```bash
dart pub global deactivate fvm
```

**`fvm list` の結果による分岐**

インストール済みの Flutter SDK が一覧表示されます。

| 表示結果 | 対応 |
|---|---|
| `3.47.4` が含まれている | Flutter SDK は導入済みです。手順 5 へ |
| 一覧が空、または `3.47.4` がない | 手順 4 で追加してください |
| 古いバージョンのみが表示される | 手順 4 で 3.47.4 を追加してください（古い版は残したままで問題ありません） |

### 手順 1. 前提ツールを確認する

**Homebrew**

```bash
brew --version
```

バージョンが表示されれば準備完了です。`command not found` の場合は [Homebrew 公式サイト](https://brew.sh/ja/) の手順で先にインストールしてください。

**Xcode コマンドラインツール**

```bash
xcode-select -p
```

`/Library/Developer/CommandLineTools` のようなパスが表示されれば準備完了です。エラーになる場合は以下を実行します（ダイアログが表示されるので「インストール」を選択してください）。

```bash
xcode-select --install
```

**Google Chrome**

```bash
ls -d "/Applications/Google Chrome.app"
```

パスが表示されれば準備完了です。エラーになる場合は以下を実行します。

```bash
brew install --cask google-chrome
```

### 手順 2. FVM をインストールする

```bash
brew install fvm
```

### 手順 3. FVM が入ったか確認する

```bash
fvm --version
```

```
4.3.1
```

バージョンが表示されれば成功です。

### 手順 4. Flutter SDK をインストールする

```bash
fvm install 3.47.4
```

初回はダウンロードに数分かかります。完了後、以下で確認します。

```bash
fvm list
```

```
Cache Directory:  /Users/ユーザー名/fvm/versions

Version │ Channel │ Flutter Version │ Dart Version
────────┼─────────┼─────────────────┼──────────────
3.47.4  │ stable  │ 3.47.4          │ 3.13.3
```

一覧に `3.47.4` が表示されれば成功です。

### 手順 5. プロジェクトで使うバージョンを固定する

Flutter プロジェクトのディレクトリ（本プロジェクトでは `frontend/`）へ移動します。

```bash
cd frontend
```

バージョンの指定がすでに済んでいるか確認します。

```bash
ls -l .fvm/flutter_sdk
```

**表示結果による分岐**

| 表示結果 | 対応 |
|---|---|
| 行の末尾に `-> /Users/ユーザー名/fvm/versions/3.47.4` と表示される | 指定済みです。手順 6 へ進んでください |
| `No such file or directory` と表示される、または `3.47.4` 以外のバージョンを指している | 下記のコマンドで指定してください |

使用するバージョンを指定します。

```bash
fvm use 3.47.4
```

```
✓ Project now uses Flutter SDK : SDK Version : 3.47.4
```

上記のように表示されれば成功です。もう一度 `ls -l .fvm/flutter_sdk` を実行し、行の末尾に `-> /Users/ユーザー名/fvm/versions/3.47.4` と表示されることを確認します。

`.fvmrc` の内容も確認します。

```bash
cat .fvmrc
```

```json
{
  "flutter": "3.47.4"
}
```

### 手順 6. 環境を確認する

```bash
fvm flutter doctor
```

```
[✓] Flutter (Channel stable, 3.47.4, on macOS, darwin-arm64)
[!] Android toolchain - develop for Android devices
[!] Xcode - develop for iOS and macOS
[✓] Chrome - develop for the web
[✓] Network resources
```

**`[✓] Flutter` と `[✓] Chrome - develop for the web` の 2 つが付いていれば、Web 開発の要件は満たしています。**
`[!] Android toolchain` と `[!] Xcode` は付いたままで問題ありません（理由は解説を参照）。

### 手順 7. 動作確認する

作業用の一時ディレクトリでサンプルアプリを作成します。

```bash
mkdir -p ~/tmp && cd ~/tmp
```

```bash
fvm flutter create flutter_hello --platforms web
```

```bash
cd flutter_hello && fvm use 3.47.4
```

Chrome で起動します。

```bash
fvm flutter run -d chrome
```

Chrome が自動で開き、カウンターアプリが表示されればセットアップ完了です。ターミナルで `q` を押すと終了します。

Web ビルドも確認します。

```bash
fvm flutter build web
```

```bash
ls build/web/index.html
```

ファイルが表示されればビルド成功です。

### 手順 8. 後片付けをする

```bash
cd ~ && rm -rf ~/tmp/flutter_hello
```

---

## 2. 各手順の解説

### 手順 0 ─ なぜ FVM のバージョンを確認するのか

FVM は「Flutter SDK を管理するツール」であり、FVM 自身と Flutter SDK は別物です。そのため確認すべき対象が 2 段階に分かれます。

| コマンド | 何を確認しているか |
|---|---|
| `fvm --version` | 管理ツールである **FVM 本体**のバージョン |
| `fvm list` | FVM が管理している **Flutter SDK** の一覧 |

FVM 本体が古いと、新しい Flutter のバージョンを認識できない場合があります。先に FVM を最新にしてから Flutter SDK を入れる、という順序が重要です。

**古い Flutter SDK は消さなくてよい理由**

FVM は複数の Flutter SDK を同時に保持できます。`~/fvm/versions/` 配下にバージョンごとのディレクトリが作られ、プロジェクトごとに使い分ける仕組みです。古いバージョンが残っていても、新しいバージョンと競合しません。

### 手順 1 ─ なぜこの 3 つが必要なのか

| ツール | 必要な理由 |
|---|---|
| Homebrew | FVM と Chrome の導入に使用します |
| Xcode コマンドラインツール | Flutter が内部で **Git** を使うために必要です |
| Google Chrome | Web アプリのデバッグ実行先として使用します |

**Xcode 本体と「コマンドラインツール」は別物です。**
Xcode は iOS / macOS アプリを開発するための IDE で、容量が十数 GB あります。一方 Xcode コマンドラインツールは Git やコンパイラなどのコマンド一式のみを提供する軽量なパッケージです。

本プロジェクトは Web のみを対象とするため、**必要なのはコマンドラインツールだけ**で、Xcode 本体のインストールは不要です。

### 手順 2 ─ なぜ Homebrew で FVM を入れるのか

FVM の公式ドキュメントではインストールスクリプト（`curl -fsSL https://fvm.app/install.sh | bash`）が推奨されていますが、本手順書では Homebrew を採用しています。

| 観点 | Homebrew | インストールスクリプト |
|---|---|---|
| 更新 | `brew upgrade fvm` | 再度スクリプトを実行 |
| 削除 | `brew uninstall fvm` | 手動で削除 |
| 他ツールとの管理 | Go・Docker と同じ方法で一元管理できる | FVM だけ管理方法が別になる |

以前は `brew tap leoafarias/fvm` というタップ（非公式リポジトリ）の追加が必要でしたが、現在 FVM は Homebrew 本体に取り込まれているため、`brew install fvm` だけで導入できます。

### 手順 4 ─ なぜ Flutter 本体を別途インストールしないのか

Flutter の一般的な導入方法では、公式サイトから SDK を取得して PATH を通します。しかし FVM を使う場合、**この作業は不要です**。

`fvm install 3.47.4` を実行すると、FVM が指定バージョンの Flutter SDK をダウンロードし、`~/fvm/versions/3.47.4/` に配置します。FVM が SDK の置き場所を管理するため、開発者が PATH を設定する必要がありません。

```
~/fvm/versions/
├── 3.47.4/     ← 本プロジェクトで使用
└── 3.44.0/     ← 別プロジェクトで使用（例）
```

### 手順 5 ─ `fvm use` は何をしているのか

`fvm use 3.47.4` を実行すると、プロジェクト直下に以下の 2 つが作られます。

| 作られるもの | 役割 | Git 管理 |
|---|---|---|
| `.fvmrc` | 使用する Flutter バージョンを記録する設定ファイル | **コミットする** |
| `.fvm/` | 指定バージョンの SDK へのシンボリックリンク | コミットしない |

**`.fvmrc` をリポジトリにコミットすることが、FVM を使う最大の目的です。**

このファイルがあれば、チームの他のメンバーがリポジトリを取得した後に `fvm install` を実行するだけで、`.fvmrc` に書かれたバージョンが自動的に導入されます。「自分の環境では動くのに、他の人の環境では動かない」という、Flutter バージョンの差異に起因する問題を防げます。

**確認に `.fvmrc` ではなく `.fvm/flutter_sdk` を使う理由**

本プロジェクトでは `frontend/.fvmrc` がすでにコミットされているため、clone した直後から `.fvmrc` は存在します。そのため `.fvmrc` があるかどうかでは、自分の Mac で `fvm use` を実行したかどうかを判断できません。`.fvm/` は各自の Mac で `fvm use` を実行したときに初めて作られるため、その中の `flutter_sdk`（SDK へのシンボリックリンク）で確認しています。

### 手順 6 ─ `[!]` が付いても問題ない理由

`flutter doctor` は、**Flutter が対応する全プラットフォーム**（Android・iOS・macOS・Web・Linux・Windows）の開発環境を一括で点検するコマンドです。

そのため、Web だけを開発する場合でも Android や iOS の項目が点検され、準備していない項目には `[!]` が付きます。これは「そのプラットフォーム向けのビルドはできない」という通知であり、**エラーではありません**。

| 表示 | 意味 |
|---|---|
| `[✓]` | その項目は利用可能 |
| `[!]` | その項目は未整備（該当プラットフォーム向けのビルド不可） |
| `[✗]` | 必須項目に問題がある |

本プロジェクトで確認すべきは `[✓] Flutter` と `[✓] Chrome - develop for the web` の 2 つのみです。

### 手順 7 ─ なぜコマンドの先頭に `fvm` を付けるのか

FVM を使う場合、Flutter のコマンドは**すべて先頭に `fvm` を付けて**実行します。ここが FVM 方式で最も間違えやすい箇所です。

| 通常の書き方 | FVM 利用時の書き方 |
|---|---|
| `flutter doctor` | `fvm flutter doctor` |
| `flutter run -d chrome` | `fvm flutter run -d chrome` |
| `flutter build web` | `fvm flutter build web` |
| `flutter pub get` | `fvm flutter pub get` |

`fvm flutter` は「`.fvmrc` に書かれたバージョンの Flutter を呼び出す」という意味です。`fvm` を付けずに `flutter` と打つと、システムに別途インストールされた Flutter（あれば）が使われてしまい、バージョンを固定した意味がなくなります。

**`--platforms web` を付けた理由**

`fvm flutter create` は、既定で Android・iOS・Web・デスクトップ用のファイルを一式生成します。`--platforms web` を指定すると Web 用のファイルのみが作られ、不要なディレクトリが生成されません。

**`fvm flutter run` と `fvm flutter build web` の違い**

| コマンド | 動作 | 用途 |
|---|---|---|
| `fvm flutter run -d chrome` | 開発用サーバーを起動し、Chrome で開く | 開発中の動作確認 |
| `fvm flutter build web` | `build/web/` に配信用ファイル一式を出力する | 本番配信用の成果物作成 |

開発中は `run` を使うことで、コードを保存するたびに画面へ即座に反映されます（ホットリロード）。`build` で出力した `build/web/` の中身は、nginx などの Web サーバーに置いて配信するための静的ファイルです。

### 補足 ─ よくあるエラーと対処

**`fvm use` で「Not a Flutter project」と表示される**

`pubspec.yaml` が存在しないディレクトリで実行しています。Flutter プロジェクトのルートディレクトリに移動してから実行してください。

**`No devices found` と表示される**

Chrome が検出されていません。以下でデバイス一覧を確認できます。

```bash
fvm flutter devices
```

`Chrome (web)` が表示されない場合は、手順 1 に戻って Google Chrome を導入してください。

**`fvm` コマンドが見つからない**

インストール直後は、すでに開いているターミナルに設定が反映されていない場合があります。ターミナルを開き直すか、以下を実行してください。

```bash
source ~/.zshrc
```
