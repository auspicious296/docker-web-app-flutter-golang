import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/repositories/auth_repository.dart';
import '../ui/auth/view/login_screen.dart';
import '../ui/core/app_dialogs.dart';
import '../ui/health/view/health_screen.dart';
import '../ui/home/view/home_screen.dart';
import '../ui/my_page/view/logout_flow.dart';
import '../ui/my_page/view/my_page_screen.dart';
import '../ui/my_page/view/password_change_screen.dart';
import '../ui/my_page/view_model/password_change_view_model.dart';
import '../ui/my_page/view_model/session_view_model.dart';
import '../ui/users/view/user_create_screen.dart';
import '../ui/users/view/user_delete_screen.dart';
import '../ui/users/view/user_edit_screen.dart';
import '../ui/users/view/user_password_reset_screen.dart';
import '../ui/users/view/users_screen.dart';
import '../ui/users/view_model/user_create_view_model.dart';
import '../ui/users/view_model/user_edit_view_model.dart';
import '../ui/users/view_model/user_password_reset_view_model.dart';
import '../ui/users/view_model/users_view_model.dart';
import 'stack_history_route_information_provider.dart';

/// ブラウザの履歴の記録を差し替えた RouteInformationProvider。
///
/// `context.push` で積んだ画面を閉じたときに、ブラウザの履歴を増やさず 1 つ戻す
/// （[StackHistoryRouteInformationProvider] を参照）。`main.dart` の
/// `MaterialApp.router` に、[router] の各部品とあわせて渡す。
final RouteInformationProvider routeInformationProvider =
    StackHistoryRouteInformationProvider(router.routeInformationProvider);

/// アプリの画面遷移の定義。
///
/// Flutter Web ではここで定義したパスがそのままブラウザの URL になる。
/// nginx 側は `try_files $uri $uri/ /index.html` を設定済みのため、
/// `https://myapp.local/health` を直接開いても表示できる。
final GoRouter router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/health', builder: (context, state) => const HealthScreen()),
    // ログイン状態のまま開いた場合は、ダイアログを出さずにマイページへ移す
    // （ADR 0015）。ログイン状態にあるかは GET /api/me で確かめる。失敗した場合は
    // 理由を問わずログイン画面を表示する（ログインし直せば済むため）。
    GoRoute(
      path: '/login',
      redirect: _redirectIfLoggedIn,
      // ログアウトなどでアプリの中から移るときは、ログインしていたユーザーの
      // メールアドレスが extra で渡される。再読み込みでは失われる（extraCodec を
      // 設定していないため）。
      builder: (context, state) => LoginScreen(
        initialEmail: state.extra is String ? state.extra! as String : null,
      ),
    ),
    // マイページ。ここから離れる（「戻る」・ブラウザの戻る）ことはログアウトを
    // 伴う（ADR 0015）。
    GoRoute(
      path: '/me',
      builder: (context, state) => const MyPageScreen(),
      onExit: _confirmLogoutOnLeave,
      routes: [
        // マイページのメニューから context.push で積む。URL はマイページと同じ
        // /me のまま（ユーザー一覧から積む画面と同じ形。ADR 0011・0015）。
        GoRoute(
          path: 'password',
          builder: (context, state) => const PasswordChangeScreen(),
          onExit: _confirmDiscardPasswordChange,
        ),
      ],
    ),
    // ページ番号や「削除済みも表示」はクエリに載せない。一覧画面を開き直したら
    // 既定（1 ページ目・削除済みを含まない）に戻す仕様のため。
    GoRoute(
      path: '/users',
      builder: (context, state) => const UsersScreen(),
      routes: [
        // 一覧から context.push で積む。go ではなく push にしているのは、一覧
        // 画面を破棄せずに残し、戻ったときに「削除済みも表示」の状態を保った
        // まま再読み込みするため。後から作る編集・削除とも挙動が揃う。
        GoRoute(
          path: 'new',
          builder: (context, state) => const UserCreateScreen(),
          onExit: _confirmDiscardInput,
        ),
        // 編集対象の ID はパスに載せる。`/users/new` は 1 セグメント、こちらは
        // 2 セグメントのため競合しない。
        GoRoute(
          path: ':id/edit',
          // 整数でない ID は URL として成立していない。利用者に見せるエラーでは
          // ないため、アラートを出さずに一覧へ送る。
          redirect: (context, state) =>
              int.tryParse(state.pathParameters['id']!) == null
              ? '/users'
              : null,
          builder: (context, state) =>
              UserEditScreen(userId: int.parse(state.pathParameters['id']!)),
          onExit: _confirmDiscardEdit,
        ),
        // API のパス（`PUT /api/users/{id}/password`）と同じ形にしている。
        // URL を見れば、どのエンドポイントを扱う画面かが分かる。
        GoRoute(
          path: ':id/password',
          redirect: (context, state) =>
              int.tryParse(state.pathParameters['id']!) == null
              ? '/users'
              : null,
          builder: (context, state) => UserPasswordResetScreen(
            userId: int.parse(state.pathParameters['id']!),
          ),
          onExit: _confirmDiscardPasswordReset,
        ),
        // 削除の API（`DELETE /api/users/{id}`）はメソッドで操作を表すためパスに
        // 操作名が入らないが、URL には操作名を付ける。`/users/{id}` では削除画面
        // であることが読み取れず、`/users/new` と同じ 2 セグメントの形にもなる。
        //
        // **この画面には `onExit` を付けない。** 離脱確認を出さず、一覧への指示も
        // `context.pop` の戻り値で返すため、ルート側ですることがない。
        GoRoute(
          path: ':id/delete',
          redirect: (context, state) =>
              int.tryParse(state.pathParameters['id']!) == null
              ? '/users'
              : null,
          builder: (context, state) =>
              UserDeleteScreen(userId: int.parse(state.pathParameters['id']!)),
        ),
      ],
    ),
  ],
);

/// 登録画面を離れる直前の確認。
///
/// `onExit` はタイトルバーの「戻る」（`context.pop`）とブラウザの戻るボタンの
/// 両方を通るため、確認が片方だけ抜けることがない。`false` を返すと遷移は中止
/// される。
///
/// 判定に使う値をルート側から読むため、入力の有無は ViewModel が真偽値で持つ
/// （入力値そのものは View の hooks にある）。`ProviderScope` は
/// `MaterialApp.router` より上にあるため、ここから到達できる。
Future<bool> _confirmDiscardInput(BuildContext context, GoRouterState state) {
  final userCreate = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(userCreateViewModelProvider);

  // 登録が完了した後と、入力が何もない場合は黙って通す。破棄するものがない。
  // チェックボックスの操作は「入力」に数えない（失われて惜しい内容ではない）。
  if (userCreate.isCompleted || !userCreate.hasInput) {
    return Future.value(true);
  }

  return showConfirmDialog(
    context,
    title: '入力内容を破棄します',
    message: '入力した内容は保存されません。\n'
        'ユーザー一覧に戻ってよろしいですか？',
  );
}

/// 編集画面を離れる直前の確認。
///
/// 仕組みは登録画面の [_confirmDiscardInput] と同じで、判定の基準だけが違う。
/// 編集画面は取得した値が最初から入っているため、「文字があるか」では常に確認が
/// 出てしまう。1 文字も触らずに「戻る」を押したときに確認を出さないよう、
/// **元の値と異なるか**で判定する。
Future<bool> _confirmDiscardEdit(BuildContext context, GoRouterState state) {
  final userId = int.parse(state.pathParameters['id']!);
  final edit = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(userEditViewModelProvider(userId));

  // 更新が完了した後、取得に失敗した後、成否が分からず閉じるときと、元の値から
  // 変わっていない場合は黙って通す。破棄するものがない。
  if (edit.isCompleted || !edit.isEdited) {
    return Future.value(true);
  }

  return showConfirmDialog(
    context,
    title: '編集内容を破棄します',
    message: '編集した内容は保存されません。\n'
        'ユーザー一覧に戻ってよろしいですか？',
  );
}

/// パスワードリセット画面を離れる直前の処理。
///
/// この関数だけ、離脱確認に加えて**一覧に対する指示**も担う。理由は、この画面が
/// 成否不明のときに画面へ留まる仕様であり（ADR 0010）、そこから「戻る」を押す
/// こと自体が「一覧を取り直せ」という指示になるためである。
///
/// 登録画面・編集画面は `context.pop(値)` で一覧へ指示を返しているが、その経路は
/// **ブラウザの戻るボタンを通らない**（go_router は値を渡せない）。`onExit` は
/// タイトルバーの「戻る」とブラウザの戻るボタンの両方を通る唯一の場所なので、
/// 指示元をここに一本化して経路による漏れをなくしている。そのため画面側は常に
/// `context.pop()`（値なし）で閉じる。
Future<bool> _confirmDiscardPasswordReset(
  BuildContext context,
  GoRouterState state,
) async {
  final userId = int.parse(state.pathParameters['id']!);
  final container = ProviderScope.containerOf(context, listen: false);
  final reset = container.read(userPasswordResetViewModelProvider(userId));

  // リセットが完了した後、取得に失敗した後、404 で閉じるときと、入力が何もない
  // 場合は確認しない。破棄するものがない。成否不明のときは入力が残っているため
  // 確認が出る（誤って戻ると、押し直せば決着するという利点まで失われる）。
  if (!reset.isCompleted && reset.hasInput) {
    final confirmed = await showConfirmDialog(
      context,
      title: '入力内容を破棄します',
      message: '入力した内容は保存されません。\n'
          'ユーザー一覧に戻ってよろしいですか？',
    );
    if (!confirmed) return false;
  }

  // 離脱が確定した。一覧に対してすべきことを 1 つだけ行う。
  //
  // 成功した後に押し直す経路はないため、この 2 つが同時に成立することはない
  // （成功時は needsListReload を下ろしている）。
  final usersViewModel = container.read(usersViewModelProvider.notifier);
  final updated = reset.updatedUser;
  if (updated != null) {
    usersViewModel.replaceUser(updated);
  } else if (reset.needsListReload) {
    usersViewModel.load();
  }

  return true;
}

/// ログイン画面を開く直前に、ログイン状態にあるかを確かめる（ADR 0015）。
///
/// ログイン状態にあればマイページへ移す。ログイン済みの利用者にログイン画面を
/// 見せると、ログイン状態が切れたと誤解させるおそれがあるためである。
Future<String?> _redirectIfLoggedIn(
  BuildContext context,
  GoRouterState state,
) async {
  try {
    await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authRepositoryProvider).fetchMe();
    return '/me';
  } on Exception {
    return null;
  }
}

/// マイページを離れる直前の処理（ADR 0015）。
///
/// 「戻る」（`go('/')`）とブラウザの戻るボタンの両方がここを通る。ログアウトの
/// 確認を出し、「はい」ならログアウトしてホーム画面へ移す。
///
/// ログアウトできた後は、この遷移を中止（`false`）したうえで、改めてホーム画面へ
/// `go` する。ブラウザの戻るボタンの行き先はホーム画面とは限らない（ログイン画面
/// など）ため、行き先をホーム画面に固定するためである。改めての `go` は
/// `allowSilentExit` が立っているため、ここを素通りする。
///
/// プログラムから画面を移すとき（ログアウトの成功・401・ロック・取得の失敗）は
/// `allowSilentExit` が立っており、確認を出さずに通す。
Future<bool> _confirmLogoutOnLeave(
  BuildContext context,
  GoRouterState state,
) async {
  final session = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(sessionViewModelProvider);
  if (session.allowSilentExit) return true;

  final result = await confirmAndLogout(context);
  switch (result) {
    case LogoutFlowResult.stayed:
      return false;
    case LogoutFlowResult.loggedOut:
      Future.microtask(() => router.go('/'));
      return false;
    case LogoutFlowResult.sessionExpired:
      Future.microtask(() => router.go('/login'));
      return false;
  }
}

/// パスワード変更画面を離れる直前の確認（ADR 0015）。
///
/// 仕組みは登録画面の [_confirmDiscardInput] と同じ。変更に成功した後、入力が
/// 何もない場合、プログラムから画面を移すとき（ログアウト・401・ロック）は確認を
/// 出さない。
Future<bool> _confirmDiscardPasswordChange(
  BuildContext context,
  GoRouterState state,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  final change = container.read(passwordChangeViewModelProvider);
  final session = container.read(sessionViewModelProvider);

  if (change.isCompleted || !change.hasInput || session.allowSilentExit) {
    return Future.value(true);
  }

  return showConfirmDialog(
    context,
    title: '入力内容を破棄します',
    message:
        '入力した内容は保存されません。\n'
        'マイページに戻ってよろしいですか？',
  );
}
