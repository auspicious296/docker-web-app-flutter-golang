# フロントエンドの状態管理・ルーティング・コード生成の選定

Flutter 公式の App Architecture ガイドが示す既定の構成は `provider` + `ChangeNotifier` によるコンストラクタ手渡しだが、本プロジェクトでは **`hooks_riverpod` + `riverpod_generator`（コード生成）+ `freezed` + `go_router`（手書き）** を採用する。ステップ 1-2（画面から API を呼び出す）の時点、つまり画面が 1 枚しかない段階で決めたのは、これらのうち Riverpod が最も後戻りコストの高い選択であり、画面が増えてからの移行では ViewModel と View の両方を書き換えることになるためである。

## 検討した選択肢

**`ChangeNotifier` + `ListenableBuilder`（公式ガイドの既定）** — 追加パッケージがゼロで学習コストも最小だが、後から Riverpod へ移行する場合のコストが最も大きい。本プロジェクトは第二段階でログイン状態をアプリ全体で共有する必要があり、その時点で結局は横断的な状態管理が要る。

**`flutter_riverpod`（hooks なし）** — `hooks_riverpod` は `flutter_riverpod` の API をすべて再エクスポートしたうえで `HookConsumerWidget` 系を追加した上位互換であり、導入コストは同じ。将来 hooks が必要になった際に pubspec と import を差し替える手間を省けるため `hooks_riverpod` を選んだ。ただし **hooks 自体は当面使わない**。View は `ConsumerWidget` で記述する。`flutter_hooks` を直接 import する段階になったら、直接依存として pubspec に追加する。

**手書きの provider（コード生成なし）** — 後から `@riverpod` へ移行すると全 provider を書き換えることになるため、最初からコード生成を採用した。`freezed` も同じ `build_runner` の上に乗るため、生成の手順を整備するコストは 1 回で済む。

**`go_router_builder`（型付きルート）** — パスの打ち間違いをコンパイル時に検出できるが、本アプリのルートは最終的に 6 本程度で、型安全の利得に対して生成物とクラス定義が増える負担が見合わない。手書きの `GoRoute(path: ...)` を採用する。必要になれば、生成されたルートは `$appRoutes` として手書きのルートと同じリストに並べられるため、後から移行も混在も可能。

**Riverpod の `AsyncValue` / experimental な Mutations（画面の状態表現）** — `AsyncValue` は loading / data / error の 3 状態しか持たず、ボタン起点の処理に必要な「まだ押していない」を表現できない。Riverpod 3 の Mutations は `MutationIdle` / `MutationPending` / `MutationError` / `MutationSuccess` の 4 状態を持ち用途に合致するが、公式が experimental と明記しているため採用を見送り、`freezed` の sealed class で 4 状態を自前で定義する方針とした。

## 結果として生じること

- **`build_runner` の実行がビルド手順に組み込まれる。** `lib/` を変更したら生成し直す必要がある。
- **生成ファイル（`*.g.dart` / `*.freezed.dart`）は Git 管理外のため、clone 直後はビルドが通らない。** 最初に `fvm dart run build_runner build` を実行する必要がある。この点は [development-guide.md](../development-guide.md) に明記している。
- 本プロジェクトは新規メンバーの学習用テンプレートを兼ねるため、採用パッケージが増えるほど最初に覚える量も増える。hooks と `go_router_builder` を今回見送ったのは、この負担を必要になるまで先送りするためである。
