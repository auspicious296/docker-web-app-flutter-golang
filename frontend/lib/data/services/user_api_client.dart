import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../config/api_config.dart';
import '../../domain/models/user_failure.dart';
import '../model/api_error_dto.dart';
import '../model/user_dto.dart';
import '../model/users_page_dto.dart';

part 'user_api_client.g.dart';

/// `/api/users` を呼び出す API クライアント（Service 層）。
///
/// エンドポイントのパスはこのクラスが持つ。`lib/config/` に置くのはベース URL
/// だけで、パスは呼び出す Service の隣に置く方針。
///
/// 一覧取得・1 件取得・ロック解除・登録・更新・パスワードリセット・削除の 7 本を
/// 持つ。
///
/// 失敗した場合は [UserFailure] を投げる。どこで失敗したのかを画面で切り分け
/// られるよう、通信・API のエラー・応答形式の 3 つに分ける。
class UserApiClient {
  const UserApiClient({required this.client});

  final http.Client client;

  /// ユーザー一覧を取得する。
  ///
  /// [includeDeleted] が `true` のときだけ `include_deleted=true` を付ける。
  /// 既定では削除済みのユーザーは含まれない。
  Future<UsersPageDto> fetchUsers({
    required int page,
    required int perPage,
    required bool includeDeleted,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/users').replace(
      queryParameters: <String, String>{
        'page': '$page',
        'per_page': '$perPage',
        if (includeDeleted) 'include_deleted': 'true',
      },
    );

    final response = await _send(() => client.get(uri));
    return _decode(response, UsersPageDto.fromJson);
  }

  /// ユーザーを 1 件取得する。編集画面が開いたときに呼ぶ。
  ///
  /// `include_deleted` は付けない。削除済みのユーザーは更新系がすべて 404 を返す
  /// ため（ADR 0004）、編集画面で開けてしまうと「編集できない画面を編集できる形で
  /// 見せる」ことになる。取得の時点で 404 になるのが正しい挙動である。
  Future<UserDto> fetchUser(int id) async {
    final uri = Uri.parse('$apiBaseUrl/api/users/$id');

    final response = await _send(() => client.get(uri));
    return _decode(response, UserDto.fromJson);
  }

  /// アカウントロックを解除する。
  ///
  /// 更新系はすべて更新後のユーザーを返す規約のため、解除後のユーザーが返る。
  /// すでにロックされていないユーザーに実行してもエラーにはならない。
  Future<UserDto> unlockUser(int id) async {
    final uri = Uri.parse('$apiBaseUrl/api/users/$id/unlock');

    final response = await _send(() => client.post(uri));
    return _decode(response, UserDto.fromJson);
  }

  /// ユーザーを登録する。
  ///
  /// 成功は **201 Created**。応答の本文は解釈しない。登録完了のダイアログには
  /// ユーザー名もメールアドレスも表示しないため、登録したユーザーの内容を画面が
  /// 一切使わないからである（ADR 0008）。
  Future<void> createUser({
    required String name,
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/users');

    final response = await _send(
      () => client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
        }),
      ),
    );

    if (response.statusCode != 201) {
      throw _apiFailure(response);
    }
  }

  /// ユーザーの名前とメールアドレスを更新する。
  ///
  /// 更新系はすべて更新後のユーザーを 200 で返す規約のため、登録（201）と違って
  /// 応答の本文を読む。一覧はこの値で該当する 1 行だけを差し替える。
  ///
  /// パスワードはこのエンドポイントでは変更できない（`PUT /api/users/{id}/password`
  /// が担当する）。
  Future<UserDto> updateUser({
    required int id,
    required String name,
    required String email,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/users/$id');

    final response = await _send(
      () => client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'email': email}),
      ),
    );
    return _decode(response, UserDto.fromJson);
  }

  /// パスワードを上書きする。現在のパスワードとの照合は行わない（管理者の操作）。
  ///
  /// **アカウントロックは解除されない。** サーバーが触るのは `password_hash` と
  /// `updated_at` だけで、`is_locked` と `failed_login_attempts` は変わらない。
  /// 一覧の「ロック状態」列は据え置きだが、「更新日時」列は差し替えが必要になる。
  ///
  /// 確認用のパスワードは送らない。入力の一致は API が知らないルールである。
  Future<UserDto> resetPassword({
    required int id,
    required String password,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/users/$id/password');

    final response = await _send(
      () => client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': password}),
      ),
    );
    return _decode(response, UserDto.fromJson);
  }

  /// ユーザーを論理削除する。
  ///
  /// 更新系はすべて更新後のユーザーを 200 で返す規約のため、削除後のユーザー
  /// （`deleted_at` と `updated_at` が入った状態）が返る。一覧が削除済みの行を
  /// 表示している場合は、この値でその 1 行を差し替える。
  ///
  /// **すでに削除済みのユーザーには 404 を返す。** サーバー側は
  /// `WHERE id = $1 AND deleted_at IS NULL` の `UPDATE` で、対象がなければ
  /// 0 行になるためである。つまり**この操作は冪等ではなく**、同じユーザーに
  /// 2 回実行すると 2 回目は 404 になる（パスワードリセットとの違い）。
  Future<UserDto> deleteUser(int id) async {
    final uri = Uri.parse('$apiBaseUrl/api/users/$id');

    final response = await _send(() => client.delete(uri));
    return _decode(response, UserDto.fromJson);
  }

  /// 通信を実行し、到達できなければ [UserNetworkFailure] を投げる。
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on Exception {
      // API まで到達できなかった（コンテナ未起動、nginx の転送設定の誤りなど）
      throw const UserFailure.network();
    }
  }

  /// 応答を DTO へ変換する。200 以外なら API のエラーとして投げ直す。
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
      // JSON として壊れている場合（FormatException）と、
      // 形は JSON でもキーや型が想定と違う場合（TypeError）の両方を含む
      throw const UserFailure.format();
    }
  }

  /// エラーレスポンスから、画面に出す日本語のメッセージを取り出す。
  ///
  /// `/api/` 配下は失敗時も必ず JSON を返すため、ここを読めない場合は API 以外
  /// （プロキシなど）が応答した可能性が高く、応答形式の異常として扱う。
  UserFailure _apiFailure(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, Object?>;
      final error = ApiErrorDto.fromJson(json).error;
      return UserFailure.api(
        code: error.code,
        message: error.message,
        fields: {for (final f in error.fields) f.field: f.message},
      );
    } on Object {
      return const UserFailure.format();
    }
  }
}

@riverpod
UserApiClient userApiClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return UserApiClient(client: client);
}
