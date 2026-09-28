import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_failure.freezed.dart';

/// ユーザー管理 API の呼び出しに失敗した理由。
///
/// 単に「失敗した」ではなく、コンテナが起動していないのか API 側の不具合なのかを
/// 画面から切り分けられるように 3 つに分ける。Service が投げ、ViewModel が受け取り、
/// View がアラートダイアログの文面へ変換する。
@freezed
sealed class UserFailure with _$UserFailure implements Exception {
  /// API まで到達できなかった（コンテナ未起動、nginx の転送設定の誤りなど）。
  const factory UserFailure.network() = UserNetworkFailure;

  /// API がエラーを返した。
  ///
  /// [message] は API が `{"error":{"message":"..."}}` で返す日本語の文面で、
  /// 画面にはこれをそのまま表示する。
  ///
  /// [code] は機械判別用のコード。登録画面は、これを見てメールアドレスの重複
  /// （409）を該当する入力欄の直下へ振り分ける（ADR 0008）。
  ///
  /// [fields] は検証エラー（400）のときだけ入る、項目名から文言への対応。
  /// 項目名は API が返す文字列（`name` / `email` / `password`）のままで、
  /// 画面の入力項目への変換は ViewModel が行う。
  const factory UserFailure.api({
    required String code,
    required String message,
    @Default(<String, String>{}) Map<String, String> fields,
  }) = UserApiFailure;

  /// 応答は得られたが、期待する JSON の形式ではなかった。
  const factory UserFailure.format() = UserFormatFailure;
}
