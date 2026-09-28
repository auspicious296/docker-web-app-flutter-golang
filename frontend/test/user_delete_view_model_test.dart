import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/services/user_api_client.dart';
import 'package:frontend/domain/models/user_failure.dart';
import 'package:frontend/ui/users/view_model/user_delete_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 対象のユーザー ID。provider が family のため、テスト側でも固定して使う。
const int _userId = 3;

/// API が返すユーザー 1 件の JSON。
///
/// [deletedAt] に値を入れると削除後のユーザー（`DELETE` の応答）になる。
String _userJson({String? deletedAt}) => jsonEncode({
  'id': _userId,
  'name': '山田 太郎',
  'email': 'yamada@example.com',
  'created_at': '2026-09-21T11:36:00+09:00',
  'updated_at': deletedAt ?? '2026-09-21T11:36:00+09:00',
  'deleted_at': deletedAt,
  'is_locked': false,
  'locked_at': null,
  'failed_login_attempts': 0,
  'last_login_at': null,
});

/// 削除の応答に入れる削除日時。
const String _deletedAt = '2026-09-23T10:00:00+09:00';

/// API クライアントを差し替えた ProviderContainer を作る。
///
/// Service（UserApiClient）と Repository は本物を通すため、リクエストの組み立てと
/// エラーレスポンスの解釈もあわせて検証できる。
ProviderContainer _createContainer(MockClient client) {
  final container = ProviderContainer(
    overrides: [
      userApiClientProvider.overrideWithValue(UserApiClient(client: client)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(userDeleteViewModelProvider(_userId), (_, _) {});
  return container;
}

http.Response _json(String body, int statusCode) => http.Response(
  body,
  statusCode,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// API のエラー応答を作る。
http.Response _error(int statusCode, String code, String message) => _json(
  jsonEncode({
    'error': {'code': code, 'message': message, 'fields': <Object>[]},
  }),
  statusCode,
);

UserDeleteViewModel _viewModel(ProviderContainer container) =>
    container.read(userDeleteViewModelProvider(_userId).notifier);

UserDeleteState _state(ProviderContainer container) =>
    container.read(userDeleteViewModelProvider(_userId));

/// GET は取得、DELETE は削除として応答するクライアントを作る。
///
/// [onDelete] を渡さない場合、削除は削除後のユーザーを 200 で返す。
MockClient _client({
  http.Response Function()? onGet,
  http.Response Function()? onDelete,
  List<http.Request>? record,
}) {
  return MockClient((request) async {
    record?.add(request);
    if (request.method == 'GET') {
      return onGet?.call() ?? _json(_userJson(), 200);
    }
    return onDelete?.call() ?? _json(_userJson(deletedAt: _deletedAt), 200);
  });
}

/// 取得を済ませた ViewModel を用意する。
Future<ProviderContainer> _loaded(MockClient client) async {
  final container = _createContainer(client);
  await _viewModel(container).load();
  return container;
}

void main() {
  group('初期状態', () {
    test('未取得・エラーなし・ローダーなし', () {
      final container = _createContainer(_client());

      final state = _state(container);
      expect(state.isLoading, isFalse);
      expect(state.target, isNull);
      expect(state.confirmationError, isNull);
    });
  });

  group('画面を開いたときの取得', () {
    test('成功すると target が入り、null が返る', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(record: requests));

      final failure = await _viewModel(container).load();

      expect(failure, isNull);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/users/$_userId');
      expect(
        requests.single.url.queryParameters.containsKey('include_deleted'),
        isFalse,
        reason: '削除済みは更新系が 404 を返すため、取得の時点で 404 になるのが正しい',
      );

      final state = _state(container);
      expect(state.target?.name, '山田 太郎');
      expect(state.target?.email, 'yamada@example.com');
      expect(state.isLoading, isFalse);
    });

    test('404 なら not_found の UserApiFailure が返る', () async {
      final container = _createContainer(
        _client(onGet: () => _error(404, 'not_found', 'ユーザーが見つかりません。')),
      );

      final failure = await _viewModel(container).load();

      expect(failure, isA<UserApiFailure>());
      expect((failure! as UserApiFailure).code, 'not_found');
      expect(_state(container).target, isNull);
      expect(_state(container).isLoading, isFalse);
    });

    test('サーバーに到達できなければ UserNetworkFailure が返る', () async {
      final container = _createContainer(
        MockClient((_) async => throw http.ClientException('failed')),
      );

      final failure = await _viewModel(container).load();

      expect(failure, isA<UserNetworkFailure>());
      expect(_state(container).isLoading, isFalse);
    });

    test('応答が JSON として壊れていれば UserFormatFailure が返る', () async {
      final container = _createContainer(
        _client(onGet: () => _json('{壊れている', 200)),
      );

      final failure = await _viewModel(container).load();

      expect(failure, isA<UserFormatFailure>());
    });
  });

  group('削除確認入力の照合', () {
    test('confirm なら通り、エラーは入らない', () async {
      final container = await _loaded(_client());

      expect(_viewModel(container).validate('confirm'), isTrue);
      expect(_state(container).confirmationError, isNull);
    });

    test('前後の空白は除いて判定する（半角・全角・タブ・複数）', () async {
      final container = await _loaded(_client());
      final viewModel = _viewModel(container);

      for (final input in [
        ' confirm',
        'confirm ',
        '  confirm  ',
        '　confirm　', // 全角スペース
        '\tconfirm\n',
        ' 　 confirm 　 ',
      ]) {
        expect(viewModel.validate(input), isTrue, reason: '入力: "$input"');
        expect(_state(container).confirmationError, isNull);
      }
    });

    test('未入力・大文字・途中の空白・打ち間違いは通らない', () async {
      final container = await _loaded(_client());
      final viewModel = _viewModel(container);

      for (final input in [
        '',
        '   ',
        'CONFIRM',
        'Confirm',
        'con firm',
        'confim',
        'ｃｏｎｆｉｒｍ', // 全角
      ]) {
        expect(viewModel.validate(input), isFalse, reason: '入力: "$input"');
        expect(
          _state(container).confirmationError,
          kDeleteConfirmationError,
          reason: '未入力と誤入力で文言を分けない',
        );
      }
    });

    test('通らなかった後に正しく入力し直すと、エラーが消える', () async {
      final container = await _loaded(_client());
      final viewModel = _viewModel(container);

      viewModel.validate('CONFIRM');
      expect(_state(container).confirmationError, isNotNull);

      expect(viewModel.validate('confirm'), isTrue);
      expect(_state(container).confirmationError, isNull);
    });

    test('照合では通信しない', () async {
      final requests = <http.Request>[];
      final container = await _loaded(_client(record: requests));
      expect(requests, hasLength(1), reason: '取得の 1 回だけ');

      _viewModel(container).validate('confirm');
      _viewModel(container).validate('CONFIRM');

      expect(requests, hasLength(1));
    });
  });

  group('削除の実行', () {
    test('成功すると success が返り、削除後のユーザーが入る', () async {
      final requests = <http.Request>[];
      final container = await _loaded(_client(record: requests));

      final outcome = await _viewModel(container).delete();

      expect(outcome, isA<UserDeleteSuccess>());
      final deleted = (outcome! as UserDeleteSuccess).deleted;
      expect(deleted.id, _userId);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.deletedAt, isNotNull);

      expect(requests.last.method, 'DELETE');
      expect(requests.last.url.path, '/api/users/$_userId');
      expect(requests.last.body, isEmpty, reason: 'ボディは送らない');
      expect(_state(container).isLoading, isFalse);
    });

    test('404 なら gone が返る（失敗としては扱わない）', () async {
      final container = await _loaded(
        _client(onDelete: () => _error(404, 'not_found', 'ユーザーが見つかりません。')),
      );

      final outcome = await _viewModel(container).delete();

      expect(outcome, isA<UserDeleteGone>());
      expect(_state(container).isLoading, isFalse);
    });

    test('サーバーに到達できなければ unknown が返る', () async {
      var loaded = false;
      final container = _createContainer(
        MockClient((request) async {
          if (!loaded) {
            loaded = true;
            return _json(_userJson(), 200);
          }
          throw http.ClientException('failed');
        }),
      );
      await _viewModel(container).load();

      final outcome = await _viewModel(container).delete();

      expect(outcome, isA<UserDeleteUnknown>());
      expect(_state(container).isLoading, isFalse);
    });

    test('500 なら failed が返り、API の文言がそのまま入る', () async {
      final container = await _loaded(
        _client(
          onDelete: () => _error(500, 'internal_error', 'サーバーエラーが発生しました。'),
        ),
      );

      final outcome = await _viewModel(container).delete();

      expect(outcome, isA<UserDeleteFailed>());
      expect((outcome! as UserDeleteFailed).message, 'サーバーエラーが発生しました。');
    });

    test('応答が JSON として壊れていれば failed が返る', () async {
      final container = await _loaded(
        _client(onDelete: () => _json('{壊れている', 200)),
      );

      final outcome = await _viewModel(container).delete();

      expect(outcome, isA<UserDeleteFailed>());
      expect(
        (outcome! as UserDeleteFailed).message,
        contains('サーバーでエラーが発生しました。'),
      );
    });

    test('実行中に呼び直しても通信は 1 回だけで、2 回目は null が返る', () async {
      final requests = <http.Request>[];
      var loaded = false;
      final container = _createContainer(
        MockClient((request) async {
          if (!loaded) {
            loaded = true;
            return _json(_userJson(), 200);
          }
          requests.add(request);
          // 1 回目の応答を遅らせ、そのあいだに 2 回目を呼ぶ
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _json(_userJson(deletedAt: _deletedAt), 200);
        }),
      );
      await _viewModel(container).load();

      final first = _viewModel(container).delete();
      final second = await _viewModel(container).delete();

      expect(second, isNull, reason: '同期的なガードで弾かれる');
      expect(await first, isA<UserDeleteSuccess>());
      expect(requests, hasLength(1), reason: 'DELETE は 1 回だけ');
    });
  });
}
