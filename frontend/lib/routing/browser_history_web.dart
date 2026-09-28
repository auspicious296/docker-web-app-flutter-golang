import 'dart:js_interop';

@JS('window.history.back')
external void _historyBack();

/// ブラウザの履歴を 1 つ戻す（`history.back()`）。
void browserHistoryBack() => _historyBack();
