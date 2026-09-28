/// 日時を `yyyy-MM-dd HH:mm:ss` の形へ整形する。値がなければ空文字を返す。
///
/// 秒まで出すのは、登録した直後に編集すると作成日時と更新日時が同じ分に収まり、
/// 秒がないと編集されたかどうかを画面から判別できなくなるため。区切りをハイフン
/// にしているのは、API が返す `2026-09-21T11:36:00+09:00` と年月日の並びを揃え、
/// `curl` の結果や pgAdmin の表示と突き合わせやすくするため。
///
/// API はオフセット付きの RFC 3339 を返し、`DateTime.parse` はそれを UTC として
/// 解釈するため、整形の前に [DateTime.toLocal] で表示するタイムゾーンへ戻す。
/// 日時は API・DB・pgAdmin のすべてで JST に揃えてある。
///
/// `intl` パッケージを使っていないのは、この 1 か所のために依存を増やす利点が
/// 薄いため。
String formatDateTime(DateTime? value) {
  if (value == null) return '';

  final local = value.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');

  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
}
