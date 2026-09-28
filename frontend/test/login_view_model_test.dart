import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/services/auth_api_client.dart';
import 'package:frontend/domain/models/auth_form_field.dart';
import 'package:frontend/ui/auth/view_model/login_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// API クライアントを差し替えた ProviderContainer を作る。
///
/// Service（AuthApiClient）と Repository は本物を通すため、CSRF トークンの取得・
/// 付与・破棄と、エラーレスポンスの解釈もあわせて検証できる。
ProviderContainer _createContainer(MockClient client) {
  final container = ProviderContainer(
    overrides: [
      authApiClientProvider.overrideWithValue(AuthApiClient(client: client)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(loginViewModelProvider, (_, _) {});
  return container;
}

http.Response _json(String body, int statusCode) => http.Response(
  body,
  statusCode,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _error(String code, String message) => jsonEncode({
  'error': {'code': code, 'message': message},
});

/// CSRF トークンの発行は毎回違う値を返し、ログインは [onLogin] で応答するクライアント。
MockClient _client({
  http.Response Function(http.Request request)? onLogin,
  List<http.Request>? requests,
}) {
  var issued = 0;
  return MockClient((request) async {
    requests?.add(request);
    if (request.url.path == '/api/csrf-token') {
      issued++;
      return _json('{"csrf_token":"token-$issued"}', 200);
    }
    return onLogin?.call(request) ?? http.Response('', 204);
  });
}

LoginViewModel _viewModel(ProviderContainer container) =>
    container.read(loginViewModelProvider.notifier);

LoginState _state(ProviderContainer container) =>
    container.read(loginViewModelProvider);

Future<LoginOutcome> _login(
  ProviderContainer container, {
  String email = 'taro@example.com',
  String password = 'password123',
}) => _viewModel(container).login(email: email, password: password);

void main() {
  group('入力の検証', () {
    test('空なら両方の欄にエラーを出し、通信しない', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(requests: requests));

      final outcome = await _login(container, email: '  ', password: '');

      expect(outcome, isA<LoginInvalid>());
      expect(_state(container).errors, {
        LoginField.email: 'メールアドレスを入力してください',
        LoginField.password: 'パスワードを入力してください',
      });
      expect(requests, isEmpty);
    });

    test('形式の検証はしない（空でなければ送る）', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(requests: requests));

      final outcome = await _login(container, email: 'abc', password: 'x');

      expect(outcome, isA<LoginSuccess>());
      expect(requests.last.url.path, '/api/login');
    });
  });

  group('ログイン', () {
    test('CSRF トークンを受け取ってから、ヘッダーに付けて送る', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(requests: requests));

      final outcome = await _login(container);

      expect(outcome, isA<LoginSuccess>());
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'GET /api/csrf-token',
        'POST /api/login',
      ]);
      final login = requests.last;
      expect(login.headers['X-CSRF-Token'], 'token-1');
      expect(jsonDecode(login.body), {
        'email': 'taro@example.com',
        'password': 'password123',
      });
      expect(_state(container).isLoading, isFalse);
    });

    test('ログインに成功したら、ログイン前のトークンを使わず取り直す', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(requests: requests));

      await _login(container);
      await _login(container);

      expect(
        requests.where((r) => r.url.path == '/api/csrf-token'),
        hasLength(2),
      );
      expect(requests.last.headers['X-CSRF-Token'], 'token-2');
    });
  });

  group('失敗', () {
    test('401 はパスワードだけをクリアさせ、API の文言を出す', () async {
      final container = _createContainer(
        _client(
          onLogin: (_) => _json(
            _error('invalid_credentials', 'メールアドレスまたはパスワードが正しくありません。'),
            401,
          ),
        ),
      );

      final outcome = await _login(container);

      expect(outcome, isA<LoginFailed>());
      outcome as LoginFailed;
      expect(outcome.message, 'メールアドレスまたはパスワードが正しくありません。');
      expect(outcome.clearPassword, isTrue);
    });

    test('403 account_locked は入力を変えない', () async {
      final container = _createContainer(
        _client(
          onLogin: (_) => _json(
            _error('account_locked', 'アカウントがロックされています。管理者に解除を依頼してください。'),
            403,
          ),
        ),
      );

      final outcome = await _login(container) as LoginFailed;

      expect(outcome.message, 'アカウントがロックされています。管理者に解除を依頼してください。');
      expect(outcome.clearPassword, isFalse);
    });

    test('429 は入力の誤りとして扱わず、入力を変えない', () async {
      const message =
          'ただいまログインの処理が集中しているため、受け付けられませんでした。\n'
          'しばらく待ってから、もう一度お試しください。';
      final container = _createContainer(
        _client(
          onLogin: (_) => _json(_error('too_many_requests', message), 429),
        ),
      );

      final outcome = await _login(container) as LoginFailed;

      expect(outcome.message, message);
      expect(outcome.clearPassword, isFalse);
    });

    test('サーバーに届かなければ、押し直しを促し入力を変えない', () async {
      final container = _createContainer(
        MockClient((_) async => throw http.ClientException('offline')),
      );

      final outcome = await _login(container) as LoginFailed;

      expect(outcome.message, 'サーバーに接続できませんでした。\nもう一度お試しください。');
      expect(outcome.clearPassword, isFalse);
    });

    test('csrf_token_invalid なら、次のログインでトークンを取り直す', () async {
      final requests = <http.Request>[];
      var rejected = false;
      final container = _createContainer(
        _client(
          requests: requests,
          onLogin: (_) {
            if (rejected) return http.Response('', 204);
            rejected = true;
            return _json(
              _error('csrf_token_invalid', 'リクエストを検証できませんでした。画面を再読み込みしてください。'),
              403,
            );
          },
        ),
      );

      final first = await _login(container) as LoginFailed;
      expect(first.message, 'リクエストを検証できませんでした。画面を再読み込みしてください。');
      expect(first.clearPassword, isFalse);

      expect(await _login(container), isA<LoginSuccess>());
      expect(requests.last.headers['X-CSRF-Token'], 'token-2');
    });

    test('API の検証エラーのうち、画面にない項目はアラートへ回す', () async {
      final container = _createContainer(
        _client(
          onLogin: (_) => _json(
            jsonEncode({
              'error': {
                'code': 'validation_error',
                'message': '入力内容に誤りがあります。',
                'fields': [
                  {'field': 'email', 'message': 'メールアドレスを入力してください'},
                  {'field': 'unknown', 'message': '不明な項目'},
                ],
              },
            }),
            400,
          ),
        ),
      );

      final outcome = await _login(container) as LoginInvalid;

      expect(outcome.alertMessage, '入力内容に誤りがあります。');
      expect(_state(container).errors, {LoginField.email: 'メールアドレスを入力してください'});
    });
  });
}
