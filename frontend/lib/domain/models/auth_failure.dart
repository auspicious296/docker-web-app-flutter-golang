import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_failure.freezed.dart';

/// ログイン・ログアウト・本人の情報・本人によるパスワード変更の API の呼び出しに
/// 失敗した理由。
///
/// 分け方はユーザー管理 API の `UserFailure` と同じ 3 つ（通信・API のエラー・
/// 応答形式）。Service が投げ、ViewModel が受け取り、画面の振る舞いへ変換する。
@freezed
sealed class AuthFailure with _$AuthFailure implements Exception {
  /// API まで到達できなかった。
  const factory AuthFailure.network() = AuthNetworkFailure;

  /// API がエラーを返した。
  ///
  /// [code] は機械判別用のコード（`invalid_credentials` / `account_locked` /
  /// `unauthenticated` / `too_many_requests` など。ADR 0014）。[message] は画面に
  /// そのまま表示できる日本語の文面。[fields] は検証エラー（400）のときだけ入る、
  /// 項目名（API の文字列のまま）から文言への対応。
  const factory AuthFailure.api({
    required String code,
    required String message,
    @Default(<String, String>{}) Map<String, String> fields,
  }) = AuthApiFailure;

  /// 応答は得られたが、期待する JSON の形式ではなかった。
  const factory AuthFailure.format() = AuthFormatFailure;
}

/// ログイン状態にないことを表す失敗か（401 `unauthenticated`。ADR 0014）。
extension AuthFailureX on AuthFailure {
  bool get isUnauthenticated =>
      this is AuthApiFailure &&
      (this as AuthApiFailure).code == 'unauthenticated';
}
