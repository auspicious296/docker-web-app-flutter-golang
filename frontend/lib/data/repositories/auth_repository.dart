import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/auth_failure.dart';
import '../../domain/models/current_user.dart';
import '../services/auth_api_client.dart';

part 'auth_repository.g.dart';

/// ログイン状態と本人の情報を扱う Repository。
///
/// **CSRF トークンをメモリに保持する。** データを変更する API を呼ぶ前に、手元に
/// トークンがなければ `GET /api/csrf-token` で受け取る（ADR 0012「手元のトークンを
/// 失ったら取り直す」）。Flutter Web は画面を再読み込みするとメモリが消えるため、
/// 再読み込みの後は、最初の送信の前に取り直すことになる。
///
/// 次のときは、手元のトークンを破棄する。次の送信の前に取り直させるためである。
/// - ログインの成功：ログイン前のトークンはログインの後には使えない（引き継がない）
/// - ログアウトの成功・401：セッションがなくなり、そのトークンは使えない
/// - 403 `csrf_token_invalid`：手元のトークンがサーバーの持つものと食い違っている
class AuthRepository {
  AuthRepository({required this.apiClient});

  final AuthApiClient apiClient;

  String? _csrfToken;

  /// ログインする。失敗した場合は [AuthFailure] を投げる。
  Future<void> login({required String email, required String password}) =>
      _withCsrfToken((token) async {
        await apiClient.login(
          email: email,
          password: password,
          csrfToken: token,
        );
        _csrfToken = null;
      });

  /// ログアウトする。失敗した場合は [AuthFailure] を投げる。
  Future<void> logout() => _withCsrfToken((token) async {
    await apiClient.logout(csrfToken: token);
    _csrfToken = null;
  });

  /// ログイン中のユーザーを取得する。失敗した場合は [AuthFailure] を投げる。
  Future<CurrentUser> fetchMe() async {
    try {
      final dto = await apiClient.fetchMe();
      return CurrentUser(id: dto.id, name: dto.name, email: dto.email);
    } on AuthFailure catch (failure) {
      _discardTokenIfNeeded(failure);
      rethrow;
    }
  }

  /// 本人のパスワードを変更する。失敗した場合は [AuthFailure] を投げる。
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _withCsrfToken(
    (token) => apiClient.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      csrfToken: token,
    ),
  );

  /// 手元の CSRF トークン（なければ受け取ったもの）で [request] を実行する。
  Future<void> _withCsrfToken(
    Future<void> Function(String token) request,
  ) async {
    try {
      final token = _csrfToken ??= await apiClient.fetchCsrfToken();
      await request(token);
    } on AuthFailure catch (failure) {
      _discardTokenIfNeeded(failure);
      rethrow;
    }
  }

  void _discardTokenIfNeeded(AuthFailure failure) {
    if (failure case AuthApiFailure(
      code: 'unauthenticated' || 'csrf_token_invalid',
    )) {
      _csrfToken = null;
    }
  }
}

/// CSRF トークンを保持するため、アプリの起動中は同じインスタンスを使い続ける
/// （keepAlive）。autoDispose にすると、画面を移るたびにトークンが失われる。
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) =>
    AuthRepository(apiClient: ref.watch(authApiClientProvider));
