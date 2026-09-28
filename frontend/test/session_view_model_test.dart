import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/services/auth_api_client.dart';
import 'package:frontend/domain/models/auth_failure.dart';
import 'package:frontend/ui/my_page/view_model/session_view_model.dart';
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

const String _meJson = '{"id":1,"name":"山田 太郎","email":"taro@example.com"}';

final http.Response _unauthenticated = _json(
  _error('unauthenticated', 'ログイン状態ではありません。ログインしてください。'),
  401,
);

/// `GET /api/me` は [onMe]、`POST /api/logout` は [onLogout] で応答するクライアント。
MockClient _client({
  http.Response Function()? onMe,
  http.Response Function()? onLogout,
  List<http.Request>? requests,
}) {
  return MockClient((request) async {
    requests?.add(request);
    switch (request.url.path) {
      case '/api/csrf-token':
        return _json('{"csrf_token":"session-token"}', 200);
      case '/api/me':
        return onMe?.call() ?? _json(_meJson, 200);
      default:
        return onLogout?.call() ?? http.Response('', 204);
    }
  });
}

SessionViewModel _viewModel(ProviderContainer container) =>
    container.read(sessionViewModelProvider.notifier);

SessionState _state(ProviderContainer container) =>
    container.read(sessionViewModelProvider);

void main() {
  group('ユーザーの取得', () {
    test('成功するとユーザーが入り、離脱確認を出す状態になる', () async {
      final container = _createContainer(_client());

      expect(await _viewModel(container).load(), isNull);

      final state = _state(container);
      expect(state.user?.name, '山田 太郎');
      expect(state.user?.email, 'taro@example.com');
      expect(state.allowSilentExit, isFalse);
      expect(state.isLoading, isFalse);
    });

    test('401 なら、確認を出さずに離れられる状態で失敗を返す', () async {
      final container = _createContainer(_client(onMe: () => _unauthenticated));

      final failure = await _viewModel(container).load();

      expect(failure?.isUnauthenticated, isTrue);
      expect(_state(container).user, isNull);
      expect(_state(container).allowSilentExit, isTrue);
    });

    test('サーバーに届かなければ、確認を出さずに離れられる状態で失敗を返す', () async {
      final container = _createContainer(
        MockClient((_) async => throw http.ClientException('offline')),
      );

      expect(await _viewModel(container).load(), isA<AuthNetworkFailure>());
      expect(_state(container).allowSilentExit, isTrue);
    });
  });

  group('ログアウト', () {
    test('CSRF トークンを付けて送り、成功したらユーザーを消す', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(requests: requests));
      await _viewModel(container).load();

      final outcome = await _viewModel(container).logout();

      expect(outcome, isA<LogoutSuccess>());
      final logout = requests.last;
      expect('${logout.method} ${logout.url.path}', 'POST /api/logout');
      expect(logout.headers['X-CSRF-Token'], 'session-token');
      expect(_state(container).user, isNull);
      expect(_state(container).allowSilentExit, isTrue);
    });

    test('401 なら unauthenticated を返し、ユーザーを消す', () async {
      final container = _createContainer(
        _client(onLogout: () => _unauthenticated),
      );
      await _viewModel(container).load();

      expect(
        await _viewModel(container).logout(),
        isA<LogoutUnauthenticated>(),
      );
      expect(_state(container).user, isNull);
      expect(_state(container).allowSilentExit, isTrue);
    });

    test('サーバーに届かなければ、押し直しを促し、ユーザーは残す', () async {
      var offline = false;
      final container = _createContainer(
        MockClient((request) async {
          if (offline) throw http.ClientException('offline');
          return _json(_meJson, 200);
        }),
      );
      await _viewModel(container).load();
      offline = true;

      final outcome = await _viewModel(container).logout() as LogoutFailed;

      expect(outcome.message, 'サーバーに接続できませんでした。\nもう一度お試しください。');
      expect(_state(container).user, isNotNull);
      expect(_state(container).allowSilentExit, isFalse);
    });

    test('その他の失敗は API の文言を返し、ユーザーは残す', () async {
      final container = _createContainer(
        _client(
          onLogout: () =>
              _json(_error('internal_error', 'サーバー内部でエラーが発生しました。'), 500),
        ),
      );
      await _viewModel(container).load();

      final outcome = await _viewModel(container).logout() as LogoutFailed;

      expect(outcome.message, 'サーバー内部でエラーが発生しました。');
      expect(_state(container).user, isNotNull);
    });
  });

  test('signedOut でユーザーを消し、確認を出さずに離れられる状態にする', () async {
    final container = _createContainer(_client());
    await _viewModel(container).load();

    _viewModel(container).signedOut();

    expect(_state(container).user, isNull);
    expect(_state(container).allowSilentExit, isTrue);
  });
}
