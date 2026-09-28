/// バックエンド API のベース URL。
///
/// 画面（Flutter）と API（Go）は nginx を経由して同じドメイン（myapp.local）で
/// 配信されるため、空文字＝相対パスでよい。別ドメインの API を呼ぶ必要が出た
/// 場合のみ、ここに `https://example.com` のような値を設定する。
const String apiBaseUrl = '';
