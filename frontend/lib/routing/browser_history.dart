/// ブラウザの履歴を 1 つ戻す処理。
///
/// Web ではブラウザの `history.back()` を呼ぶ。Web 以外（`flutter test` など）では
/// ブラウザの履歴が存在しないため、何もしない。
library;

export 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart';
