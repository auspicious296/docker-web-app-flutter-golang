import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/services/auth_api_client.dart';
import 'package:frontend/domain/models/auth_form_field.dart';
import 'package:frontend/ui/my_page/view_model/password_change_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ProviderContainer _createContainer(MockClient client) {
  final container = ProviderContainer(
    overrides: [
      authApiClientProvider.overrideWithValue(AuthApiClient(client: client)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(passwordChangeViewModelProvider, (_, _) {});
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

/// `PUT /api/me/password` を [onPut] で応答するクライアント。
MockClient _client({
  http.Response Function(http.Request request)? onPut,
  List<http.Request>? requests,
}) {
  return MockClient((request) async {
    requests?.add(request);
    if (request.url.path == '/api/csrf-token') {
      return _json('{"csrf_token":"session-token"}', 200);
    }
    return onPut?.call(request) ?? http.Response('', 204);
  });
}

PasswordChangeViewModel _viewModel(ProviderContainer container) =>
    container.read(passwordChangeViewModelProvider.notifier);

PasswordChangeState _state(ProviderContainer container) =>
    container.read(passwordChangeViewModelProvider);

Future<PasswordChangeOutcome> _change(
  ProviderContainer container, {
  String current = 'password123',
  String newPassword = 'newpass456',
  String? confirmation,
}) => _viewModel(container).change(
  currentPassword: current,
  newPassword: newPassword,
  newPasswordConfirmation: confirmation ?? newPassword,
);

void main() {
  group('入力の検証', () {
    test('すべて空なら 3 欄にエラーを出し、通信しない', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(requests: requests));

      final outcome = await _change(
        container,
        current: '',
        newPassword: '',
        confirmation: '',
      );

      expect(outcome, isA<PasswordChangeInvalid>());
      expect(_state(container).errors, {
        PasswordChangeField.currentPassword: '現在のパスワードを入力してください',
        PasswordChangeField.newPassword: '新しいパスワードを入力してください',
        PasswordChangeField.newPasswordConfirmation: '確認用のパスワードを入力してください',
      });
      expect(requests, isEmpty);
    });

    test('新しいパスワードは登録時と同じ規則で検証し、確認用の不一致も出す', () async {
      final container = _createContainer(_client());

      await _change(container, newPassword: 'short', confirmation: 'other');

      expect(_state(container).errors, {
        PasswordChangeField.newPassword: 'パスワードは 8 文字以上 72 文字以内で入力してください',
        PasswordChangeField.newPasswordConfirmation: 'パスワードが一致しません',
      });
    });
  });

  group('変更', () {
    test('成功すると、確認用を送らずに CSRF トークンを付けて送り、完了になる', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(requests: requests));

      expect(await _change(container), isA<PasswordChangeSuccess>());

      final put = requests.last;
      expect('${put.method} ${put.url.path}', 'PUT /api/me/password');
      expect(put.headers['X-CSRF-Token'], 'session-token');
      expect(jsonDecode(put.body), {
        'current_password': 'password123',
        'new_password': 'newpass456',
      });
      expect(_state(container).isCompleted, isTrue);
      expect(_state(container).isLoading, isFalse);
    });

    test('現在のパスワードの誤りは、その欄のエラーになる', () async {
      final container = _createContainer(
        _client(
          onPut: (_) => _json(
            jsonEncode({
              'error': {
                'code': 'validation_error',
                'message': '入力内容に誤りがあります。',
                'fields': [
                  {'field': 'current_password', 'message': '現在のパスワードが正しくありません'},
                ],
              },
            }),
            400,
          ),
        ),
      );

      final outcome = await _change(container) as PasswordChangeInvalid;

      expect(outcome.alertMessage, isNull);
      expect(_state(container).errors, {
        PasswordChangeField.currentPassword: '現在のパスワードが正しくありません',
      });
      expect(_state(container).isCompleted, isFalse);
    });

    test('403 account_locked は locked を返す', () async {
      final container = _createContainer(
        _client(
          onPut: (_) => _json(
            _error('account_locked', 'アカウントがロックされています。管理者に解除を依頼してください。'),
            403,
          ),
        ),
      );

      final outcome = await _change(container) as PasswordChangeLocked;

      expect(outcome.message, 'アカウントがロックされています。管理者に解除を依頼してください。');
    });

    test('401 は unauthenticated を返す', () async {
      final container = _createContainer(
        _client(
          onPut: (_) => _json(
            _error('unauthenticated', 'ログイン状態ではありません。ログインしてください。'),
            401,
          ),
        ),
      );

      expect(await _change(container), isA<PasswordChangeUnauthenticated>());
    });

    test('サーバーに届かなければ成否不明とし、離脱確認は出す状態のまま', () async {
      final container = _createContainer(
        MockClient((_) async => throw http.ClientException('offline')),
      );

      expect(await _change(container), isA<PasswordChangeUnknown>());
      expect(_state(container).isCompleted, isFalse);
    });

    test('その他の失敗は API の文言を返す', () async {
      final container = _createContainer(
        _client(
          onPut: (_) => _json(
            _error('csrf_token_invalid', 'リクエストを検証できませんでした。画面を再読み込みしてください。'),
            403,
          ),
        ),
      );

      final outcome = await _change(container) as PasswordChangeFailed;

      expect(outcome.message, 'リクエストを検証できませんでした。画面を再読み込みしてください。');
    });
  });

  test('入力の有無を記録する', () {
    final container = _createContainer(_client());

    _viewModel(container).setHasInput(hasInput: true);
    expect(_state(container).hasInput, isTrue);

    _viewModel(container).setHasInput(hasInput: false);
    expect(_state(container).hasInput, isFalse);
  });
}
