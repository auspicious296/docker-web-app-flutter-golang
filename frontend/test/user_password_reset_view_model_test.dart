import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/services/user_api_client.dart';
import 'package:frontend/domain/models/user_failure.dart';
import 'package:frontend/domain/models/user_form_field.dart';
import 'package:frontend/ui/users/view_model/user_password_reset_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 対象のユーザー ID。provider が family のため、テスト側でも固定して使う。
const int _userId = 3;

/// API が返すユーザー 1 件の JSON。
String _userJson({bool isLocked = false}) => jsonEncode({
  'id': _userId,
  'name': '山田 太郎',
  'email': 'yamada@example.com',
  'created_at': '2026-09-21T11:36:00+09:00',
  'updated_at': '2026-09-21T11:36:00+09:00',
  'deleted_at': null,
  'is_locked': isLocked,
  'locked_at': isLocked ? '2026-09-22T09:00:00+09:00' : null,
  'failed_login_attempts': isLocked ? 5 : 0,
  'last_login_at': null,
});

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
  container.listen(userPasswordResetViewModelProvider(_userId), (_, _) {});
  return container;
}

http.Response _json(String body, int statusCode) => http.Response(
  body,
  statusCode,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

UserPasswordResetViewModel _viewModel(ProviderContainer container) =>
    container.read(userPasswordResetViewModelProvider(_userId).notifier);

UserPasswordResetState _state(ProviderContainer container) =>
    container.read(userPasswordResetViewModelProvider(_userId));

/// GET は取得、PUT はリセットとして応答するクライアントを作る。
MockClient _client({
  http.Response Function(http.Request request)? onPut,
  List<http.Request>? requests,
  String? getBody,
  int getStatus = 200,
}) {
  return MockClient((request) async {
    requests?.add(request);
    if (request.method == 'GET') {
      return _json(getBody ?? _userJson(), getStatus);
    }
    return onPut?.call(request) ?? _json(_userJson(), 200);
  });
}

/// 取得を済ませた状態の container を作る。
Future<ProviderContainer> _loaded(MockClient client) async {
  final container = _createContainer(client);
  await _viewModel(container).load();
  return container;
}

/// 正しい入力でリセットを実行する。
Future<UserPasswordResetOutcome> _reset(
  ProviderContainer container, {
  String password = 'password123',
  String? passwordConfirmation,
}) => _viewModel(container).reset(
  password: password,
  passwordConfirmation: passwordConfirmation ?? password,
);

void main() {
  group('初期状態', () {
    test('対象を持たず、入力も一覧への指示もない', () {
      final container = _createContainer(_client());

      final state = _state(container);
      expect(state.isLoading, isFalse);
      expect(state.errors, isEmpty);
      expect(state.target, isNull);
      expect(state.hasInput, isFalse);
      expect(state.isCompleted, isFalse);
      expect(state.updatedUser, isNull);
      expect(state.needsListReload, isFalse);
    });
  });

  group('画面を開いたときの取得', () {
    test('成功すると対象が入り、GET は include_deleted を付けない', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(requests: requests));

      expect(await _viewModel(container).load(), isNull);

      final state = _state(container);
      expect(state.target?.name, '山田 太郎');
      expect(state.target?.email, 'yamada@example.com');

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/users/$_userId');
      expect(requests.single.url.queryParameters, isEmpty);
    });

    test('404 なら失敗を返し、閉じられる状態になるが一覧は取り直さない', () async {
      final container = _createContainer(
        _client(
          getBody: '{"error":{"code":"not_found","message":"ユーザーが見つかりません。"}}',
          getStatus: 404,
        ),
      );

      expect(await _viewModel(container).load(), isA<UserApiFailure>());

      final state = _state(container);
      expect(state.target, isNull);
      expect(state.isCompleted, isTrue);
      // 一覧の内容は何も変わっていないため、取り直す必要がない
      expect(state.needsListReload, isFalse);
      expect(state.updatedUser, isNull);
    });

    test('サーバーに届かなければ失敗を返す', () async {
      final container = _createContainer(
        MockClient((_) async => throw const SocketExceptionStub()),
      );

      expect(await _viewModel(container).load(), isA<UserNetworkFailure>());
    });
  });

  group('クライアント側の検証で弾いたとき', () {
    test('未入力なら通信せず、両方の欄にエラーが入る', () async {
      final requests = <http.Request>[];
      final container = await _loaded(_client(requests: requests));
      requests.clear();

      final outcome = await _reset(
        container,
        password: '',
        passwordConfirmation: '',
      );

      expect(outcome, isA<UserPasswordResetInvalid>());
      expect(requests, isEmpty);
      expect(_state(container).errors.keys, {
        UserFormField.password,
        UserFormField.passwordConfirmation,
      });
    });

    test('8 文字未満なら通信しない', () async {
      final requests = <http.Request>[];
      final container = await _loaded(_client(requests: requests));
      requests.clear();

      expect(
        await _reset(container, password: 'short1'),
        isA<UserPasswordResetInvalid>(),
      );
      expect(requests, isEmpty);
      expect(_state(container).errors[UserFormField.password], isNotNull);
    });

    test('ASCII の印字可能文字以外なら通信しない', () async {
      final container = await _loaded(_client());

      expect(
        await _reset(container, password: 'ぱすわーど123'),
        isA<UserPasswordResetInvalid>(),
      );
      expect(
        _state(container).errors[UserFormField.password],
        'パスワードは半角英数字と記号（スペースを除く）で入力してください',
      );
    });

    test('確認用が一致しなければ確認用の欄にエラーが入る', () async {
      final requests = <http.Request>[];
      final container = await _loaded(_client(requests: requests));
      requests.clear();

      final outcome = await _reset(
        container,
        password: 'password123',
        passwordConfirmation: 'password124',
      );

      expect(outcome, isA<UserPasswordResetInvalid>());
      expect(requests, isEmpty);
      expect(
        _state(container).errors[UserFormField.passwordConfirmation],
        'パスワードが一致しません',
      );
      expect(_state(container).errors.containsKey(UserFormField.password), isFalse);
    });
  });

  group('リセットに成功したとき', () {
    test('PUT で password だけを送る（確認用は送らない）', () async {
      late http.Request sent;
      final container = await _loaded(
        _client(
          onPut: (request) {
            sent = request;
            return _json(_userJson(), 200);
          },
        ),
      );

      expect(await _reset(container), isA<UserPasswordResetSuccess>());

      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(sent.method, 'PUT');
      expect(sent.url.path, '/api/users/$_userId/password');
      expect(body, {'password': 'password123'});
    });

    test('更新後のユーザーを持ち、一覧の取り直しは要らない状態になる', () async {
      final container = await _loaded(_client());

      final outcome = await _reset(container);

      expect((outcome as UserPasswordResetSuccess).updated.id, _userId);
      final state = _state(container);
      expect(state.isLoading, isFalse);
      expect(state.isCompleted, isTrue);
      expect(state.updatedUser?.id, _userId);
      expect(state.needsListReload, isFalse);
      expect(state.errors, isEmpty);
    });

    test('ロック中のユーザーなら、更新後の値でもロックが残っている', () async {
      final container = await _loaded(
        _client(onPut: (_) => _json(_userJson(isLocked: true), 200)),
      );

      final outcome = await _reset(container);

      // View はこの値を見て、完了ダイアログに赤い一文を足すかを決める
      expect((outcome as UserPasswordResetSuccess).updated.isLocked, isTrue);
    });
  });

  group('API がエラーを返したとき', () {
    test('400 の fields をパスワード欄へ振り分ける', () async {
      final container = await _loaded(
        _client(
          onPut: (_) => _json(
            '{"error":{"code":"validation_error","message":"入力内容に誤りがあります。",'
            '"fields":[{"field":"password","message":"パスワードを入力してください"}]}}',
            400,
          ),
        ),
      );

      final outcome = await _reset(container);

      expect((outcome as UserPasswordResetInvalid).alertMessage, isNull);
      expect(
        _state(container).errors[UserFormField.password],
        'パスワードを入力してください',
      );
    });

    test('変換できない field はアラートへ回す', () async {
      final container = await _loaded(
        _client(
          onPut: (_) => _json(
            '{"error":{"code":"validation_error","message":"入力内容に誤りがあります。",'
            '"fields":[{"field":"secret","message":"未知の項目"}]}}',
            400,
          ),
        ),
      );

      final outcome = await _reset(container);

      expect(
        (outcome as UserPasswordResetInvalid).alertMessage,
        '入力内容に誤りがあります。',
      );
      expect(_state(container).errors, isEmpty);
    });

    test('404 は gone として扱い、閉じて一覧を取り直す状態になる', () async {
      final container = await _loaded(
        _client(
          onPut: (_) => _json(
            '{"error":{"code":"not_found","message":"ユーザーが見つかりません。"}}',
            404,
          ),
        ),
      );

      final outcome = await _reset(container);

      expect(
        (outcome as UserPasswordResetGone).message,
        'ユーザーが見つかりません。',
      );
      final state = _state(container);
      expect(state.isCompleted, isTrue);
      expect(state.needsListReload, isTrue);
      expect(state.updatedUser, isNull);
    });

    test('その他のコードはアラートの文言にする', () async {
      final container = await _loaded(
        _client(
          onPut: (_) => _json(
            '{"error":{"code":"internal_error",'
            '"message":"サーバー内部でエラーが発生しました。"}}',
            500,
          ),
        ),
      );

      final outcome = await _reset(container);

      expect(
        (outcome as UserPasswordResetFailed).message,
        'サーバー内部でエラーが発生しました。',
      );
      // 画面には留まるため、閉じる指示も一覧への指示も立たない
      expect(_state(container).isCompleted, isFalse);
      expect(_state(container).needsListReload, isFalse);
    });

    test('応答が JSON でなければ、再試行を促す文言になる', () async {
      final container = await _loaded(
        _client(onPut: (_) => http.Response('<html>502</html>', 502)),
      );

      final outcome = await _reset(container);

      expect(
        (outcome as UserPasswordResetFailed).message,
        'サーバーでエラーが発生しました。\nしばらく待ってから、もう一度お試しください。',
      );
    });
  });

  group('サーバーに届かなかったとき', () {
    /// 取得は成功し、その後の PUT だけが失敗するクライアント。
    MockClient putFails({int failures = 1}) {
      var putCount = 0;
      return MockClient((request) async {
        if (request.method == 'GET') return _json(_userJson(), 200);
        putCount++;
        if (putCount <= failures) throw const SocketExceptionStub();
        return _json(_userJson(), 200);
      });
    }

    test('成否不明として扱い、画面に留まったまま一覧の取り直しを予約する', () async {
      final container = await _loaded(putFails());

      final outcome = await _reset(container);

      expect(outcome, isA<UserPasswordResetUnknown>());
      final state = _state(container);
      expect(state.needsListReload, isTrue);
      // 画面に留まって押し直せるようにするため、閉じる指示は立てない
      expect(state.isCompleted, isFalse);
      expect(state.updatedUser, isNull);
    });

    test('何度失敗しても実行し直せる', () async {
      final container = await _loaded(putFails(failures: 3));

      expect(await _reset(container), isA<UserPasswordResetUnknown>());
      expect(await _reset(container), isA<UserPasswordResetUnknown>());
      expect(await _reset(container), isA<UserPasswordResetUnknown>());

      expect(_state(container).needsListReload, isTrue);
      expect(_state(container).isCompleted, isFalse);
    });

    test('押し直して成功すると、取り直しの予約は下りて 1 行差し替えに切り替わる', () async {
      final container = await _loaded(putFails());

      expect(await _reset(container), isA<UserPasswordResetUnknown>());
      expect(_state(container).needsListReload, isTrue);

      expect(await _reset(container), isA<UserPasswordResetSuccess>());

      final state = _state(container);
      expect(state.updatedUser?.id, _userId);
      // 差し替えで一覧は正しくなるため、取り直しは不要になる（二重に走らない）
      expect(state.needsListReload, isFalse);
      expect(state.isCompleted, isTrue);
    });
  });

  group('入力の有無', () {
    test('同じ値なら状態を作り直さない', () async {
      final container = await _loaded(_client());

      final before = _state(container);
      _viewModel(container).setHasInput(hasInput: false);

      expect(identical(_state(container), before), isTrue);
    });

    test('切り替えると状態に反映される', () async {
      final container = await _loaded(_client());

      _viewModel(container).setHasInput(hasInput: true);
      expect(_state(container).hasInput, isTrue);

      _viewModel(container).setHasInput(hasInput: false);
      expect(_state(container).hasInput, isFalse);
    });
  });
}

/// 通信の失敗を模した例外。
///
/// `UserApiClient` は `Exception` を捕まえて `UserFailure.network()` に変換する
/// ため、種類は問わない。
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
