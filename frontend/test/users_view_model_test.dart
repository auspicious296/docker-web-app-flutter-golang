import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/services/user_api_client.dart';
import 'package:frontend/domain/models/user_failure.dart';
import 'package:frontend/ui/users/view_model/users_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// API クライアントを差し替えた ProviderContainer を作る。
///
/// Service（UserApiClient）と Repository は本物を通すため、クエリの組み立てと
/// DTO からドメインモデルへの変換もあわせて検証できる。
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
  container.listen(usersViewModelProvider, (_, _) {});
  return container;
}

/// JSON を UTF-8 として返す応答を作る。
http.Response _json(String body, [int statusCode = 200]) => http.Response(
  body,
  statusCode,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _user({
  required int id,
  String name = '山田 太郎',
  String email = 'yamada@example.com',
  String? deletedAt,
  bool isLocked = false,
  String? lockedAt,
  int failedLoginAttempts = 0,
  String? lastLoginAt,
}) {
  String nullable(String? v) => v == null ? 'null' : '"$v"';
  return '{"id":$id,"name":"$name","email":"$email",'
      '"created_at":"2026-09-21T11:36:00+09:00",'
      '"updated_at":"2026-09-21T11:36:00+09:00",'
      '"deleted_at":${nullable(deletedAt)},'
      '"is_locked":$isLocked,"locked_at":${nullable(lockedAt)},'
      '"failed_login_attempts":$failedLoginAttempts,'
      '"last_login_at":${nullable(lastLoginAt)}}';
}

String _page(List<String> users, {int page = 1, int total = 0}) =>
    '{"users":[${users.join(',')}],"page":$page,"per_page":20,"total":$total}';

void main() {
  group('初期状態', () {
    test('空・1 ページ目・削除済みは含まない・未選択', () {
      final container = _createContainer(
        MockClient((_) async => _json(_page([]))),
      );

      final state = container.read(usersViewModelProvider);
      expect(state.users, isEmpty);
      expect(state.page, 1);
      expect(state.perPage, 20);
      expect(state.total, 0);
      expect(state.includeDeleted, isFalse);
      expect(state.selectedUserId, isNull);
      expect(state.isLoading, isFalse);
      expect(state.loadFailure, isNull);
      expect(state.canCreate, isTrue);
    });
  });

  group('一覧の取得', () {
    test('成功すると users と total が入り、既定では include_deleted を送らない', () async {
      Uri? requested;
      final container = _createContainer(
        MockClient((request) async {
          requested = request.url;
          return _json(_page([_user(id: 1), _user(id: 2)], total: 2));
        }),
      );

      final failure = await container
          .read(usersViewModelProvider.notifier)
          .load();

      expect(failure, isNull);
      expect(requested!.path, '/api/users');
      expect(requested!.queryParameters['page'], '1');
      expect(requested!.queryParameters['per_page'], '20');
      expect(requested!.queryParameters.containsKey('include_deleted'), isFalse);

      final state = container.read(usersViewModelProvider);
      expect(state.users.map((u) => u.id), [1, 2]);
      expect(state.total, 2);
      expect(state.users.first.name, '山田 太郎');
      expect(state.loadFailure, isNull);
    });

    test('日時が DateTime に変換され、null の日時は null のままになる', () async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            _page([
              _user(
                id: 1,
                deletedAt: '2026-09-22T09:00:00+09:00',
                lastLoginAt: '2026-09-21T12:00:00+09:00',
              ),
            ], total: 1),
          ),
        ),
      );

      await container.read(usersViewModelProvider.notifier).load();

      final user = container.read(usersViewModelProvider).users.single;
      expect(user.createdAt, isA<DateTime>());
      expect(user.deletedAt, isNotNull);
      expect(user.isDeleted, isTrue);
      expect(user.lockedAt, isNull);
      expect(user.lastLoginAt, DateTime.parse('2026-09-21T12:00:00+09:00'));
    });

    test('接続できないと network の失敗になり、新規登録も押せなくなる', () async {
      final container = _createContainer(
        MockClient((_) async => throw http.ClientException('切断')),
      );

      final failure = await container
          .read(usersViewModelProvider.notifier)
          .load();

      expect(failure, isA<UserNetworkFailure>());
      final state = container.read(usersViewModelProvider);
      expect(state.users, isEmpty);
      expect(state.total, 0);
      expect(state.loadFailure, isA<UserNetworkFailure>());
      expect(state.canCreate, isFalse);
    });

    test('API がエラーを返すと、その message を持つ失敗になる', () async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            '{"error":{"code":"internal_error","message":"サーバー内部で問題が発生しました"}}',
            500,
          ),
        ),
      );

      final failure = await container
          .read(usersViewModelProvider.notifier)
          .load();

      expect(failure, isA<UserApiFailure>());
      expect(
        (failure! as UserApiFailure).message,
        'サーバー内部で問題が発生しました',
      );
      expect(container.read(usersViewModelProvider).canCreate, isFalse);
    });

    test('応答が JSON として読めないと format の失敗になる', () async {
      final container = _createContainer(
        MockClient((_) async => _json('<html>502</html>')),
      );

      final failure = await container
          .read(usersViewModelProvider.notifier)
          .load();

      expect(failure, isA<UserFormatFailure>());
      expect(container.read(usersViewModelProvider).canCreate, isFalse);
    });
  });

  group('行の選択', () {
    Future<ProviderContainer> load() async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            _page([
              _user(id: 1),
              _user(id: 2, isLocked: true, lockedAt: '2026-09-22T09:00:00+09:00'),
              _user(id: 3, deletedAt: '2026-09-22T09:00:00+09:00'),
              _user(
                id: 4,
                isLocked: true,
                lockedAt: '2026-09-22T09:00:00+09:00',
                deletedAt: '2026-09-22T09:00:00+09:00',
              ),
            ], total: 4),
          ),
        ),
      );
      await container.read(usersViewModelProvider.notifier).load();
      return container;
    }

    test('タップで選択され、同じ行の再タップで解除される', () async {
      final container = await load();
      final viewModel = container.read(usersViewModelProvider.notifier);

      viewModel.toggleSelection(1);
      expect(container.read(usersViewModelProvider).selectedUserId, 1);

      viewModel.toggleSelection(1);
      expect(container.read(usersViewModelProvider).selectedUserId, isNull);
    });

    test('別の行をタップするとそちらへ移る', () async {
      final container = await load();
      final viewModel = container.read(usersViewModelProvider.notifier);

      viewModel
        ..toggleSelection(1)
        ..toggleSelection(2);

      expect(container.read(usersViewModelProvider).selectedUserId, 2);
    });

    test('通常の行を選ぶと編集系は押せ、ロック解除は押せない', () async {
      final container = await load();
      container.read(usersViewModelProvider.notifier).toggleSelection(1);

      final state = container.read(usersViewModelProvider);
      expect(state.canOperateSelected, isTrue);
      expect(state.canUnlock, isFalse);
    });

    test('ロック中の行を選ぶとロック解除も押せる', () async {
      final container = await load();
      container.read(usersViewModelProvider.notifier).toggleSelection(2);

      final state = container.read(usersViewModelProvider);
      expect(state.canOperateSelected, isTrue);
      expect(state.canUnlock, isTrue);
    });

    test('削除済みの行を選ぶと、新規登録以外はすべて押せない', () async {
      final container = await load();
      container.read(usersViewModelProvider.notifier).toggleSelection(3);

      final state = container.read(usersViewModelProvider);
      expect(state.selectedUserId, 3, reason: '行の選択自体はできる');
      expect(state.canOperateSelected, isFalse);
      expect(state.canUnlock, isFalse);
      expect(state.canCreate, isTrue);
    });

    test('削除済みかつロック中の行は、削除済みの判定が優先される', () async {
      final container = await load();
      container.read(usersViewModelProvider.notifier).toggleSelection(4);

      final state = container.read(usersViewModelProvider);
      expect(state.canOperateSelected, isFalse);
      expect(state.canUnlock, isFalse);
    });
  });

  group('ページ送りと表示の切り替え', () {
    test('ページを送るとクエリの page が変わり、選択が解除される', () async {
      Uri? requested;
      final container = _createContainer(
        MockClient((request) async {
          requested = request.url;
          final page = int.parse(request.url.queryParameters['page']!);
          return _json(_page([_user(id: page)], page: page, total: 40));
        }),
      );

      final viewModel = container.read(usersViewModelProvider.notifier);
      await viewModel.load();
      viewModel.toggleSelection(1);
      expect(container.read(usersViewModelProvider).selectedUserId, 1);

      await viewModel.goToPage(2);

      expect(requested!.queryParameters['page'], '2');
      final state = container.read(usersViewModelProvider);
      expect(state.page, 2);
      expect(state.selectedUserId, isNull);
      expect(state.isFirstPage, isFalse);
      expect(state.isLastPage, isTrue);
      expect(state.totalPages, 2);
    });

    test('「削除済みも表示」をオンにすると include_deleted が付き、1 ページ目へ戻る', () async {
      Uri? requested;
      final container = _createContainer(
        MockClient((request) async {
          requested = request.url;
          return _json(_page([_user(id: 1)], page: 1, total: 40));
        }),
      );

      final viewModel = container.read(usersViewModelProvider.notifier);
      await viewModel.goToPage(2);
      viewModel.toggleSelection(1);

      await viewModel.setIncludeDeleted(includeDeleted: true);

      expect(requested!.queryParameters['include_deleted'], 'true');
      expect(requested!.queryParameters['page'], '1');
      final state = container.read(usersViewModelProvider);
      expect(state.includeDeleted, isTrue);
      expect(state.page, 1);
      expect(state.selectedUserId, isNull);
    });

    test('件数の表示に使う範囲が正しく求まる', () async {
      final container = _createContainer(
        MockClient((request) async {
          final page = int.parse(request.url.queryParameters['page']!);
          return _json(
            _page([for (var i = 0; i < 17; i++) _user(id: i)], page: page, total: 37),
          );
        }),
      );

      final viewModel = container.read(usersViewModelProvider.notifier);
      await viewModel.goToPage(2);

      final state = container.read(usersViewModelProvider);
      expect(state.totalPages, 2);
      expect(state.firstRowNumber, 21);
      expect(state.lastRowNumber, 37);
    });
  });

  group('アカウントロックの解除', () {
    test('成功するとその行だけ差し替わり、選択は維持される', () async {
      var unlocked = false;
      final container = _createContainer(
        MockClient((request) async {
          if (request.method == 'POST') {
            unlocked = true;
            return _json(_user(id: 2, name: '佐藤 花子'));
          }
          return _json(
            _page([
              _user(id: 1),
              _user(
                id: 2,
                name: '佐藤 花子',
                isLocked: true,
                lockedAt: '2026-09-22T09:00:00+09:00',
                failedLoginAttempts: 5,
              ),
            ], total: 2),
          );
        }),
      );

      final viewModel = container.read(usersViewModelProvider.notifier);
      await viewModel.load();
      viewModel.toggleSelection(2);

      final failure = await viewModel.unlockSelected();

      expect(failure, isNull);
      expect(unlocked, isTrue);
      final state = container.read(usersViewModelProvider);
      expect(state.users.length, 2, reason: '一覧は取り直さない');
      expect(state.users.first.id, 1, reason: '他の行は変わらない');
      expect(state.users.last.isLocked, isFalse);
      expect(state.selectedUserId, 2, reason: '選択は維持される');
      expect(state.canUnlock, isFalse, reason: '解除後はボタンが無効になる');
    });

    test('失敗しても一覧は空にならず、新規登録も押せたままになる', () async {
      final container = _createContainer(
        MockClient((request) async {
          if (request.method == 'POST') {
            return _json(
              '{"error":{"code":"not_found","message":"ユーザーが見つかりません"}}',
              404,
            );
          }
          return _json(
            _page([
              _user(
                id: 1,
                isLocked: true,
                lockedAt: '2026-09-22T09:00:00+09:00',
              ),
            ], total: 1),
          );
        }),
      );

      final viewModel = container.read(usersViewModelProvider.notifier);
      await viewModel.load();
      viewModel.toggleSelection(1);

      final failure = await viewModel.unlockSelected();

      expect(failure, isA<UserApiFailure>());
      final state = container.read(usersViewModelProvider);
      expect(state.users, hasLength(1), reason: '一覧の内容は有効なまま');
      expect(state.loadFailure, isNull);
      expect(state.canCreate, isTrue);
      expect(state.selectedUserId, 1);
    });

    test('未選択のときは何もしない', () async {
      final container = _createContainer(
        MockClient((_) async => _json(_page([_user(id: 1)], total: 1))),
      );

      final viewModel = container.read(usersViewModelProvider.notifier);
      await viewModel.load();

      expect(await viewModel.unlockSelected(), isNull);
    });
  });

  group('1 行の差し替え', () {
    test('該当する行だけが変わり、ページ・表示条件・選択は動かない', () async {
      final container = _createContainer(
        MockClient(
          (_) async => _json(
            _page([
              _user(id: 1, name: '山田 太郎', email: 'yamada@example.com'),
              _user(id: 2, name: '佐藤 次郎', email: 'sato@example.com'),
            ], page: 2, total: 42),
          ),
        ),
      );

      final viewModel = container.read(usersViewModelProvider.notifier);
      await viewModel.goToPage(2);
      viewModel.toggleSelection(2);

      final before = container.read(usersViewModelProvider);
      viewModel.replaceUser(
        before.users[1].copyWith(name: '佐藤 花子', email: 'hanako@example.com'),
      );

      final state = container.read(usersViewModelProvider);
      expect(state.users[0].name, '山田 太郎', reason: '他の行は変わらない');
      expect(state.users[1].name, '佐藤 花子');
      expect(state.users[1].email, 'hanako@example.com');
      expect(state.users, hasLength(2), reason: '行の数と並びは変わらない');
      expect(state.page, 2);
      expect(state.total, 42);
      expect(state.includeDeleted, isFalse);
      expect(state.selectedUserId, 2, reason: '選択は維持される');
      expect(state.selectedUser?.name, '佐藤 花子');
    });

    test('表示中のページにない行を渡しても何も起きない', () async {
      final container = _createContainer(
        MockClient((_) async => _json(_page([_user(id: 1)], total: 1))),
      );

      final viewModel = container.read(usersViewModelProvider.notifier);
      await viewModel.load();

      final absent = container
          .read(usersViewModelProvider)
          .users
          .first
          .copyWith(id: 99, name: '別のページのユーザー');
      viewModel.replaceUser(absent);

      final state = container.read(usersViewModelProvider);
      expect(state.users, hasLength(1));
      expect(state.users.single.id, 1);
      expect(state.users.single.name, '山田 太郎');
    });
  });

  group('空になったページの是正', () {
    test('2 ページ目が 0 件で総件数が残っていれば、1 ページ目を読み直す', () async {
      final requested = <String?>[];
      final container = _createContainer(
        MockClient((request) async {
          final page = request.url.queryParameters['page'];
          requested.add(page);
          // 2 ページ目の最後の 1 件が削除され、総件数が 20 に減った状況
          return page == '2'
              ? _json(_page([], page: 2, total: 20))
              : _json(_page([_user(id: 1)], total: 20));
        }),
      );

      final failure = await container
          .read(usersViewModelProvider.notifier)
          .goToPage(2);

      expect(failure, isNull);
      expect(requested, ['2', '1'], reason: '2 ページ目の後に 1 ページ目を読む');

      final state = container.read(usersViewModelProvider);
      expect(state.page, 1);
      expect(state.users, hasLength(1));
      expect(state.total, 20);
      expect(state.firstRowNumber, 1);
      expect(state.lastRowNumber, 1, reason: '件数表示が壊れない');
      expect(state.isLoading, isFalse);
    });

    test('1 ページ目が 0 件で総件数も 0 なら、読み直さない', () async {
      final requested = <String?>[];
      final container = _createContainer(
        MockClient((request) async {
          requested.add(request.url.queryParameters['page']);
          return _json(_page([]));
        }),
      );

      await container.read(usersViewModelProvider.notifier).load();

      expect(requested, ['1'], reason: '0 ページ目を要求しない');

      final state = container.read(usersViewModelProvider);
      expect(state.page, 1);
      expect(state.users, isEmpty);
      expect(state.total, 0);
      expect(state.firstRowNumber, 0);
      expect(state.lastRowNumber, 0);
    });

    test('1 ページ目が 0 件でも総件数が残っていれば、読み直さない', () async {
      final requested = <String?>[];
      final container = _createContainer(
        MockClient((request) async {
          requested.add(request.url.queryParameters['page']);
          return _json(_page([], total: 20));
        }),
      );

      await container.read(usersViewModelProvider.notifier).load();

      expect(requested, ['1'], reason: '0 ページ目を要求しない');
      expect(container.read(usersViewModelProvider).page, 1);
    });

    test('2 ページ目に行があれば、読み直さない', () async {
      final requested = <String?>[];
      final container = _createContainer(
        MockClient((request) async {
          requested.add(request.url.queryParameters['page']);
          return _json(_page([_user(id: 21)], page: 2, total: 21));
        }),
      );

      await container.read(usersViewModelProvider.notifier).goToPage(2);

      expect(requested, ['2']);

      final state = container.read(usersViewModelProvider);
      expect(state.page, 2);
      expect(state.users, hasLength(1));
      expect(state.total, 21);
    });
  });
}
