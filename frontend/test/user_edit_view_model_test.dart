import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/services/user_api_client.dart';
import 'package:frontend/domain/models/user_failure.dart';
import 'package:frontend/domain/models/user_form_field.dart';
import 'package:frontend/ui/users/view_model/user_edit_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 編集対象のユーザー ID。provider が family のため、テスト側でも固定して使う。
const int _userId = 3;

/// API が返すユーザー 1 件の JSON。
String _userJson({
  String name = '山田 太郎',
  String email = 'yamada@example.com',
}) => jsonEncode({
  'id': _userId,
  'name': name,
  'email': email,
  'created_at': '2026-09-21T11:36:00+09:00',
  'updated_at': '2026-09-21T11:36:00+09:00',
  'deleted_at': null,
  'is_locked': false,
  'locked_at': null,
  'failed_login_attempts': 0,
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
  container.listen(userEditViewModelProvider(_userId), (_, _) {});
  return container;
}

http.Response _json(String body, int statusCode) => http.Response(
  body,
  statusCode,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

UserEditViewModel _viewModel(ProviderContainer container) =>
    container.read(userEditViewModelProvider(_userId).notifier);

UserEditState _state(ProviderContainer container) =>
    container.read(userEditViewModelProvider(_userId));

/// GET は取得、PUT は更新として応答するクライアントを作る。
///
/// [onPut] を渡すと PUT の応答を差し替えられる。[requests] を渡すと、飛んだ
/// リクエストがすべて記録される（「通信しない」ことの検証に使う）。
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

void main() {
  group('初期状態', () {
    test('取得前は元の値を持たず、編集もされていない', () {
      final container = _createContainer(_client());

      final state = _state(container);
      expect(state.isLoading, isFalse);
      expect(state.errors, isEmpty);
      expect(state.original, isNull);
      expect(state.isEdited, isFalse);
      expect(state.isCompleted, isFalse);
    });
  });

  group('画面を開いたときの取得', () {
    test('成功すると元の値が入り、GET は include_deleted を付けない', () async {
      final requests = <http.Request>[];
      final container = _createContainer(_client(requests: requests));

      expect(await _viewModel(container).load(), isNull);

      final state = _state(container);
      expect(state.isLoading, isFalse);
      expect(state.original?.name, '山田 太郎');
      expect(state.original?.email, 'yamada@example.com');

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/users/$_userId');
      expect(requests.single.url.queryParameters, isEmpty);
    });

    test('404 なら失敗を返し、離脱確認を出さずに閉じられる状態になる', () async {
      final container = _createContainer(
        _client(
          getBody: '{"error":{"code":"not_found","message":"ユーザーが見つかりません。"}}',
          getStatus: 404,
        ),
      );

      final failure = await _viewModel(container).load();

      expect(failure, isA<UserApiFailure>());
      expect(_state(container).original, isNull);
      expect(_state(container).isCompleted, isTrue);
    });

    test('サーバーに届かなければ失敗を返す', () async {
      final container = _createContainer(
        MockClient((_) async => throw const SocketExceptionStub()),
      );

      expect(await _viewModel(container).load(), isA<UserNetworkFailure>());
    });
  });

  group('変更がないとき', () {
    test('通信せず notEdited を返す', () async {
      final requests = <http.Request>[];
      final container = await _loaded(_client(requests: requests));
      requests.clear();

      final outcome = await _viewModel(container).update(
        name: '山田 太郎',
        email: 'yamada@example.com',
      );

      expect(outcome, isA<UserEditNotEdited>());
      expect(requests, isEmpty);
      expect(_state(container).isCompleted, isFalse);
    });

    test('前後の空白・全角スペースだけの差は変更とみなさない', () async {
      final requests = <http.Request>[];
      final container = await _loaded(_client(requests: requests));
      requests.clear();

      final outcome = await _viewModel(container).update(
        name: '　山田　太郎　',
        email: '  yamada@example.com  ',
      );

      expect(outcome, isA<UserEditNotEdited>());
      expect(requests, isEmpty);
    });

    test('メールアドレスの大文字小文字を変えた場合は変更とみなす', () async {
      final requests = <http.Request>[];
      final container = await _loaded(_client(requests: requests));
      requests.clear();

      final outcome = await _viewModel(container).update(
        name: '山田 太郎',
        email: 'Yamada@example.com',
      );

      expect(outcome, isA<UserEditSuccess>());
      expect(requests.single.method, 'PUT');
    });

    test('前回のエラー表示は消える', () async {
      final container = await _loaded(_client());

      // 一度エラーを出してから、元の値に戻して押し直す
      await _viewModel(container).update(name: '', email: 'yamada@example.com');
      expect(_state(container).errors, isNotEmpty);

      final outcome = await _viewModel(
        container,
      ).update(name: '山田 太郎', email: 'yamada@example.com');

      expect(outcome, isA<UserEditNotEdited>());
      expect(_state(container).errors, isEmpty);
    });
  });

  group('クライアント側の検証で弾いたとき', () {
    test('通信せず、該当する欄にエラーが入る', () async {
      final requests = <http.Request>[];
      final container = await _loaded(_client(requests: requests));
      requests.clear();

      final outcome = await _viewModel(
        container,
      ).update(name: '', email: 'これはメールアドレスではない');

      expect(outcome, isA<UserEditInvalid>());
      expect(requests, isEmpty);
      expect(_state(container).errors.keys, {
        UserFormField.name,
        UserFormField.email,
      });
    });
  });

  group('更新に成功したとき', () {
    test('整形した値を PUT で送り、更新後のユーザーを返す', () async {
      late http.Request sent;
      final container = await _loaded(
        _client(
          onPut: (request) {
            sent = request;
            return _json(
              _userJson(name: '山田 花子', email: 'hanako@example.com'),
              200,
            );
          },
        ),
      );

      final outcome = await _viewModel(
        container,
      ).update(name: '　山田　花子　', email: '  hanako@example.com  ');

      expect(outcome, isA<UserEditSuccess>());
      expect((outcome as UserEditSuccess).updated.name, '山田 花子');

      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(sent.method, 'PUT');
      expect(sent.url.path, '/api/users/$_userId');
      expect(body['name'], '山田 花子');
      expect(body['email'], 'hanako@example.com');
      // パスワードはこのエンドポイントでは変更できない
      expect(body.containsKey('password'), isFalse);
    });

    test('離脱確認を出さない状態になる', () async {
      final container = await _loaded(_client());

      await _viewModel(
        container,
      ).update(name: '山田 花子', email: 'yamada@example.com');

      final state = _state(container);
      expect(state.isLoading, isFalse);
      expect(state.isCompleted, isTrue);
      expect(state.errors, isEmpty);
    });
  });

  group('API がエラーを返したとき', () {
    Future<UserEditOutcome> updateWith(String body, int status) async {
      final container = await _loaded(
        _client(onPut: (_) => _json(body, status)),
      );
      return _viewModel(
        container,
      ).update(name: '山田 花子', email: 'hanako@example.com');
    }

    test('409（重複）はメールアドレス欄の直下に出す', () async {
      final container = await _loaded(
        _client(
          onPut: (_) => _json(
            '{"error":{"code":"email_already_exists",'
            '"message":"このメールアドレスは既に登録されています"}}',
            409,
          ),
        ),
      );

      final outcome = await _viewModel(
        container,
      ).update(name: '山田 花子', email: 'hanako@example.com');

      expect(outcome, isA<UserEditInvalid>());
      expect(
        _state(container).errors[UserFormField.email],
        'このメールアドレスは既に登録されています',
      );
    });

    test('409（削除済みユーザーと衝突）も同じ扱いになる', () async {
      final outcome = await updateWith(
        '{"error":{"code":"email_belongs_to_deleted_user",'
        '"message":"このメールアドレスは削除済みのユーザーが使用しているため登録できません"}}',
        409,
      );

      expect(outcome, isA<UserEditInvalid>());
    });

    test('400 の fields を各入力欄へ振り分ける', () async {
      final container = await _loaded(
        _client(
          onPut: (_) => _json(
            '{"error":{"code":"validation_error","message":"入力内容に誤りがあります。",'
            '"fields":[{"field":"name","message":"名前を入力してください"}]}}',
            400,
          ),
        ),
      );

      final outcome = await _viewModel(
        container,
      ).update(name: '山田 花子', email: 'hanako@example.com');

      expect((outcome as UserEditInvalid).alertMessage, isNull);
      expect(_state(container).errors[UserFormField.name], '名前を入力してください');
    });

    test('変換できない field はアラートへ回す', () async {
      final container = await _loaded(
        _client(
          onPut: (_) => _json(
            '{"error":{"code":"validation_error","message":"入力内容に誤りがあります。",'
            '"fields":[{"field":"nickname","message":"未知の項目"}]}}',
            400,
          ),
        ),
      );

      final outcome = await _viewModel(
        container,
      ).update(name: '山田 花子', email: 'hanako@example.com');

      expect((outcome as UserEditInvalid).alertMessage, '入力内容に誤りがあります。');
      expect(_state(container).errors, isEmpty);
    });

    test('404 は gone として扱い、一覧へ戻れる状態にする', () async {
      final container = await _loaded(
        _client(
          onPut: (_) => _json(
            '{"error":{"code":"not_found","message":"ユーザーが見つかりません。"}}',
            404,
          ),
        ),
      );

      final outcome = await _viewModel(
        container,
      ).update(name: '山田 花子', email: 'hanako@example.com');

      expect((outcome as UserEditGone).message, 'ユーザーが見つかりません。');
      expect(_state(container).isCompleted, isTrue);
    });

    test('その他のコードはアラートの文言にする', () async {
      final outcome = await updateWith(
        '{"error":{"code":"internal_error",'
        '"message":"サーバー内部でエラーが発生しました。"}}',
        500,
      );

      expect((outcome as UserEditFailed).message, 'サーバー内部でエラーが発生しました。');
    });

    test('応答が JSON でなければ、再試行を促す文言になる', () async {
      final container = await _loaded(
        _client(onPut: (_) => http.Response('<html>502</html>', 502)),
      );

      final outcome = await _viewModel(
        container,
      ).update(name: '山田 花子', email: 'hanako@example.com');

      expect(
        (outcome as UserEditFailed).message,
        'サーバーでエラーが発生しました。\nしばらく待ってから、もう一度お試しください。',
      );
    });
  });

  group('サーバーに届かなかったとき', () {
    test('成否不明として扱い、一覧へ戻れる状態にする', () async {
      var loaded = false;
      final container = _createContainer(
        MockClient((request) async {
          if (!loaded) {
            loaded = true;
            return _json(_userJson(), 200);
          }
          throw const SocketExceptionStub();
        }),
      );
      await _viewModel(container).load();

      final outcome = await _viewModel(
        container,
      ).update(name: '山田 花子', email: 'hanako@example.com');

      expect(outcome, isA<UserEditUnknown>());
      expect(_state(container).isCompleted, isTrue);
    });
  });

  group('編集の有無', () {
    test('元の値と同じあいだは編集されていない扱いになる', () async {
      final container = await _loaded(_client());

      _viewModel(
        container,
      ).syncEdited(name: '山田 太郎', email: 'yamada@example.com');
      expect(_state(container).isEdited, isFalse);

      _viewModel(
        container,
      ).syncEdited(name: '山田 花子', email: 'yamada@example.com');
      expect(_state(container).isEdited, isTrue);

      // 打ち直して元へ戻したら、確認は出さない
      _viewModel(
        container,
      ).syncEdited(name: '山田 太郎', email: 'yamada@example.com');
      expect(_state(container).isEdited, isFalse);
    });

    test('同じ値なら状態を作り直さない', () async {
      final container = await _loaded(_client());

      final before = _state(container);
      _viewModel(
        container,
      ).syncEdited(name: '山田 太郎', email: 'yamada@example.com');

      expect(identical(_state(container), before), isTrue);
    });

    test('取得が終わっていなければ編集されていない扱いになる', () {
      final container = _createContainer(_client());

      _viewModel(container).syncEdited(name: 'なにか', email: 'a@example.com');

      expect(_state(container).isEdited, isFalse);
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
