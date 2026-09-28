import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/services/user_api_client.dart';
import 'package:frontend/domain/models/user_form_field.dart';
import 'package:frontend/ui/users/view_model/user_create_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// API クライアントを差し替えた ProviderContainer を作る。
///
/// Service（UserApiClient）と Repository は本物を通すため、リクエストの組み立てと
/// エラーレスポンスの解釈もあわせて検証できる。
///
/// `listen` しているのは、画面（View）が ViewModel を `watch` している状態を
/// 模すため。これがないと ViewModel が誰にも監視されず、自動破棄の対象になる。
ProviderContainer _createContainer(MockClient client) {
  final container = ProviderContainer(
    overrides: [
      userApiClientProvider.overrideWithValue(UserApiClient(client: client)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(userCreateViewModelProvider, (_, _) {});
  return container;
}

http.Response _json(String body, int statusCode) => http.Response(
  body,
  statusCode,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 正しい入力で登録を実行する。
Future<UserCreateOutcome> _register(
  ProviderContainer container, {
  String name = '山田 太郎',
  String email = 'yamada@example.com',
  String password = 'password123',
  String? passwordConfirmation,
}) => container
    .read(userCreateViewModelProvider.notifier)
    .register(
      name: name,
      email: email,
      password: password,
      passwordConfirmation: passwordConfirmation ?? password,
    );

void main() {
  group('初期状態', () {
    test('読み込み中でなく、エラーも入力もない', () {
      final container = _createContainer(
        MockClient((_) async => _json('', 201)),
      );

      final state = container.read(userCreateViewModelProvider);
      expect(state.isLoading, isFalse);
      expect(state.errors, isEmpty);
      expect(state.hasInput, isFalse);
      expect(state.isCompleted, isFalse);
    });
  });

  group('登録に成功したとき', () {
    test('201 を成功として扱い、離脱確認を出さない状態になる', () async {
      final container = _createContainer(
        MockClient((_) async => _json('', 201)),
      );

      final outcome = await _register(container);

      expect(outcome, isA<UserCreateSuccess>());
      final state = container.read(userCreateViewModelProvider);
      expect(state.isLoading, isFalse);
      expect(state.isCompleted, isTrue);
      expect(state.errors, isEmpty);
    });

    test('整形した値を送る（前後の空白の除去、全角スペースの置換）', () async {
      late http.Request sent;
      final container = _createContainer(
        MockClient((request) async {
          sent = request;
          return _json('', 201);
        }),
      );

      await _register(
        container,
        name: '　山田　太郎　',
        email: '  yamada@example.com  ',
      );

      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/users');
      expect(body['name'], '山田 太郎');
      expect(body['email'], 'yamada@example.com');
      expect(body['password'], 'password123');
      // 確認用パスワードは API に送らない
      expect(body.containsKey('password_confirmation'), isFalse);
    });

    test('200 は成功として扱わない（登録は 201 を返すため）', () async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            '{"error":{"code":"internal_error","message":"想定外の応答"}}',
            200,
          ),
        ),
      );

      expect(await _register(container), isA<UserCreateFailed>());
    });
  });

  group('クライアント側の検証で弾いたとき', () {
    test('リクエストを送らず、項目ごとのエラーが state に入る', () async {
      var requested = false;
      final container = _createContainer(
        MockClient((_) async {
          requested = true;
          return _json('', 201);
        }),
      );

      final outcome = await _register(container, name: '', password: 'short');

      expect(outcome, isA<UserCreateInvalid>());
      expect((outcome as UserCreateInvalid).alertMessage, isNull);
      expect(requested, isFalse, reason: '検証で弾いたので通信してはいけない');

      final errors = container.read(userCreateViewModelProvider).errors;
      expect(errors.keys, contains(UserFormField.name));
      expect(errors.keys, contains(UserFormField.password));
    });

    test('パスワードの不一致を検出する', () async {
      final container = _createContainer(
        MockClient((_) async => _json('', 201)),
      );

      await _register(
        container,
        password: 'password123',
        passwordConfirmation: 'password124',
      );

      expect(
        container.read(userCreateViewModelProvider).errors[
            UserFormField.passwordConfirmation],
        'パスワードが一致しません',
      );
    });

    test('押し直すと前回のエラーはリセットされる', () async {
      final container = _createContainer(
        MockClient((_) async => _json('', 201)),
      );

      await _register(container, name: '');
      expect(
        container.read(userCreateViewModelProvider).errors,
        isNotEmpty,
      );

      await _register(container);
      expect(container.read(userCreateViewModelProvider).errors, isEmpty);
    });
  });

  group('メールアドレスが重複したとき', () {
    test('409 はアラートではなくメールアドレス欄のエラーになる', () async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            '{"error":{"code":"email_already_exists",'
            '"message":"このメールアドレスは既に登録されています"}}',
            409,
          ),
        ),
      );

      final outcome = await _register(container);

      expect(outcome, isA<UserCreateInvalid>());
      expect((outcome as UserCreateInvalid).alertMessage, isNull);
      expect(
        container.read(userCreateViewModelProvider).errors[UserFormField.email],
        'このメールアドレスは既に登録されています',
      );
      expect(container.read(userCreateViewModelProvider).isCompleted, isFalse);
    });

    test('削除済みユーザーとの重複も同じ扱いになる', () async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            '{"error":{"code":"email_belongs_to_deleted_user",'
            '"message":"このメールアドレスは削除済みのユーザーが使用しているため登録できません"}}',
            409,
          ),
        ),
      );

      await _register(container);

      expect(
        container.read(userCreateViewModelProvider).errors[UserFormField.email],
        'このメールアドレスは削除済みのユーザーが使用しているため登録できません',
      );
    });
  });

  group('API が検証エラーを返したとき', () {
    test('fields を項目ごとのエラーに振り分ける', () async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            '{"error":{"code":"validation_error","message":"入力内容に誤りがあります",'
            '"fields":[{"field":"name","message":"名前が不正です"},'
            '{"field":"password","message":"パスワードが不正です"}]}}',
            400,
          ),
        ),
      );

      final outcome = await _register(container);

      expect(outcome, isA<UserCreateInvalid>());
      expect((outcome as UserCreateInvalid).alertMessage, isNull);
      final errors = container.read(userCreateViewModelProvider).errors;
      expect(errors[UserFormField.name], '名前が不正です');
      expect(errors[UserFormField.password], 'パスワードが不正です');
    });

    test('画面に対応する欄がない field はアラートへ回す', () async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            '{"error":{"code":"validation_error","message":"入力内容に誤りがあります",'
            '"fields":[{"field":"name","message":"名前が不正です"},'
            '{"field":"unknown_field","message":"知らない項目です"}]}}',
            400,
          ),
        ),
      );

      final outcome = await _register(container);

      // 振り分けられた分は欄の下に、振り分けられなかった分はアラートに出す
      expect(
        (outcome as UserCreateInvalid).alertMessage,
        '入力内容に誤りがあります',
      );
      expect(
        container.read(userCreateViewModelProvider).errors[UserFormField.name],
        '名前が不正です',
      );
    });
  });

  group('登録に失敗したとき', () {
    test('サーバー内部エラーは API の文言をそのまま返す', () async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            '{"error":{"code":"internal_error",'
            '"message":"サーバー内部でエラーが発生しました"}}',
            500,
          ),
        ),
      );

      final outcome = await _register(container);

      expect(
        (outcome as UserCreateFailed).message,
        'サーバー内部でエラーが発生しました',
      );
      expect(container.read(userCreateViewModelProvider).isCompleted, isFalse);
    });

    test('応答が JSON でなければ、再試行を促す文言になる', () async {
      final container = _createContainer(
        MockClient((_) async => http.Response('<html>502</html>', 502)),
      );

      final outcome = await _register(container);

      expect(
        (outcome as UserCreateFailed).message,
        'サーバーでエラーが発生しました。\nしばらく待ってから、もう一度お試しください。',
      );
    });
  });

  group('サーバーに届かなかったとき', () {
    test('成否不明として扱い、一覧へ戻れる状態にする', () async {
      final container = _createContainer(
        MockClient((_) async => throw http.ClientException('接続できません')),
      );

      final outcome = await _register(container);

      expect(outcome, isA<UserCreateUnknown>());
      final state = container.read(userCreateViewModelProvider);
      expect(state.isLoading, isFalse);
      // 登録されたかどうか分からないため、破棄の確認は出さずに一覧で確認させる
      expect(state.isCompleted, isTrue);
    });
  });

  group('入力の有無', () {
    test('同じ値なら状態を作り直さない', () {
      final container = _createContainer(
        MockClient((_) async => _json('', 201)),
      );
      final viewModel = container.read(userCreateViewModelProvider.notifier);

      final before = container.read(userCreateViewModelProvider);
      viewModel.setHasInput(hasInput: false);
      expect(
        identical(before, container.read(userCreateViewModelProvider)),
        isTrue,
      );

      viewModel.setHasInput(hasInput: true);
      expect(container.read(userCreateViewModelProvider).hasInput, isTrue);
    });
  });
}
