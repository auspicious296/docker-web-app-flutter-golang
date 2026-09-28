import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../config/api_config.dart';
import '../../domain/models/auth_failure.dart';
import '../model/api_error_dto.dart';
import '../model/csrf_token_dto.dart';
import '../model/me_dto.dart';

part 'auth_api_client.g.dart';

/// ログイン・ログアウト・本人の情報・本人によるパスワード変更の API を呼び出す
/// クライアント（Service 層）。Web 用の API だけを扱う（ADR 0012）。
///
/// セッション ID は HttpOnly の Cookie で運ばれ、画面と API は同じオリジンのため、
/// ブラウザが自動で送る。このクラスはセッション ID に触れない。データを変更する
/// API（`POST` / `PUT`）には、渡された CSRF トークンを `X-CSRF-Token` ヘッダーで
/// 付ける。トークンの保持と取り直しは Repository が担う。
///
/// 失敗した場合は [AuthFailure] を投げる。
class AuthApiClient {
  const AuthApiClient({required this.client});

  final http.Client client;

  static const String _csrfHeader = 'X-CSRF-Token';

  /// CSRF トークンを受け取る（ADR 0012）。
  ///
  /// ログイン中なら今のセッションのトークン、未ログインならログイン前のトークンが
  /// 返る（後者は署名付きの Cookie も同時に発行される）。
  Future<String> fetchCsrfToken() async {
    final uri = Uri.parse('$apiBaseUrl/api/csrf-token');

    final response = await _send(() => client.get(uri));
    return _decode(response, CsrfTokenDto.fromJson).csrfToken;
  }

  /// ログインする（Web 用）。成功は **204**（本文なし。ADR 0014）。
  Future<void> login({
    required String email,
    required String password,
    required String csrfToken,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/login');

    final response = await _send(
      () => client.post(
        uri,
        headers: {'Content-Type': 'application/json', _csrfHeader: csrfToken},
        body: jsonEncode({'email': email, 'password': password}),
      ),
    );
    _expectNoContent(response);
  }

  /// ログアウトする。成功は **204**（本文なし。ADR 0014）。
  Future<void> logout({required String csrfToken}) async {
    final uri = Uri.parse('$apiBaseUrl/api/logout');

    final response = await _send(
      () => client.post(uri, headers: {_csrfHeader: csrfToken}),
    );
    _expectNoContent(response);
  }

  /// ログイン中のユーザーの情報を取得する。
  Future<MeDto> fetchMe() async {
    final uri = Uri.parse('$apiBaseUrl/api/me');

    final response = await _send(() => client.get(uri));
    return _decode(response, MeDto.fromJson);
  }

  /// 本人のパスワードを変更する。成功は **204**（本文なし。ADR 0014）。
  ///
  /// 確認用のパスワードは送らない。入力の一致は API が知らないルールである。
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String csrfToken,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/me/password');

    final response = await _send(
      () => client.put(
        uri,
        headers: {'Content-Type': 'application/json', _csrfHeader: csrfToken},
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      ),
    );
    _expectNoContent(response);
  }

  /// 通信を実行し、到達できなければ [AuthNetworkFailure] を投げる。
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on Exception {
      throw const AuthFailure.network();
    }
  }

  /// 204 以外なら API のエラーとして投げる。
  void _expectNoContent(http.Response response) {
    if (response.statusCode != 204) {
      throw _apiFailure(response);
    }
  }

  /// 応答を DTO へ変換する。200 以外なら API のエラーとして投げる。
  T _decode<T>(
    http.Response response,
    T Function(Map<String, Object?>) fromJson,
  ) {
    if (response.statusCode != 200) {
      throw _apiFailure(response);
    }

    try {
      final json = jsonDecode(response.body) as Map<String, Object?>;
      return fromJson(json);
    } on Object {
      throw const AuthFailure.format();
    }
  }

  /// エラーレスポンスから、コード・メッセージ・項目別の内訳を取り出す。
  ///
  /// nginx が返す 429（呼び出し回数の制限）も同じ形の JSON である（ADR 0014）。
  /// 読めない場合は API 以外（プロキシなど）が応答した可能性が高く、応答形式の
  /// 異常として扱う。
  AuthFailure _apiFailure(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, Object?>;
      final error = ApiErrorDto.fromJson(json).error;
      return AuthFailure.api(
        code: error.code,
        message: error.message,
        fields: {for (final f in error.fields) f.field: f.message},
      );
    } on Object {
      return const AuthFailure.format();
    }
  }
}

/// アプリの起動中は同じインスタンスを使い続ける（keepAlive）。
///
/// Repository が CSRF トークンを保持するため、Repository とあわせて破棄されない
/// ようにしている。
@Riverpod(keepAlive: true)
AuthApiClient authApiClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return AuthApiClient(client: client);
}
