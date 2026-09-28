import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../domain/models/user_failure.dart';
import '../../core/app_dialogs.dart';
import '../../core/back_app_bar.dart';
import '../../core/content_width.dart';
import '../../core/loading_overlay.dart';
import '../view_model/user_delete_view_model.dart';
import '../view_model/user_edit_view_model.dart';
import '../view_model/users_view_model.dart';
import 'users_action_bar.dart';
import 'users_paginator.dart';
import 'users_table.dart';

/// ユーザー一覧画面。
///
/// 画面を開いた時点で一覧を取得する。この画面の操作はワンタップで通信が走るため
/// （誤タップしやすく、連打で API を叩ける）、いずれも確認ダイアログを挟む。
/// 実行中は画面全体をローダーが覆う。
///
/// 入力を伴う画面（登録・編集）はこの限りではない。入力そのものが意思表示を
/// 兼ねるため、確認ダイアログを挟まない。
///
/// `ConsumerStatefulWidget` にしているのは、初回の取得を `initState` から始める
/// ためだけで、画面の状態は ViewModel が持つ。
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  @override
  void initState() {
    super.initState();
    // build の最中に状態を変更できないため、最初のフレームの後に取得を始める
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  UsersViewModel get _viewModel => ref.read(usersViewModelProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(usersViewModelProvider);

    return Scaffold(
      appBar: const BackAppBar(title: 'ユーザー管理'),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(kScreenPadding),
            // 中身を共通のコンテンツ幅の箱に収めて中央へ置き、余った幅は左右に
            // 均等に残す。ボタン群・テーブル・ページ送りを同じ幅に揃えることで、
            // 右寄せの要素がテーブルの右端と一致し、タイトルバーの「戻る」ボタン
            // とも左端が揃う。
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidthFor(constraints.maxWidth),
                  child: Column(
                    // 子に幅いっぱいを与える。既定（中央寄せ）のままだと、ボタン群
                    // が内容の幅に縮んで中央に寄り、左寄せ・右寄せが効かない。
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      UsersActionBar(
                        state: state,
                        onReload: _onReload,
                        onCreate: _onCreate,
                        onEdit: _onEdit,
                        onResetPassword: _onResetPassword,
                        onDelete: _onDelete,
                        onUnlock: _onUnlock,
                        onIncludeDeletedChanged: _onIncludeDeletedChanged,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: UsersTable(
                          users: state.users,
                          selectedUserId: state.selectedUserId,
                          onRowTap: _viewModel.toggleSelection,
                        ),
                      ),
                      const SizedBox(height: 8),
                      UsersPaginator(
                        state: state,
                        onPageChanged: _onPageChanged,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (state.isLoading) const Positioned.fill(child: LoadingOverlay()),
        ],
      ),
    );
  }

  /// 画面を開いたときの取得。
  Future<void> _load() async {
    await _runLoad(_viewModel.load());
  }

  /// 「一覧再読み込み」。
  ///
  /// 取得に失敗している状況は不安定なことが多いため、連打で API を叩かないよう
  /// 確認を挟む。
  Future<void> _onReload() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '一覧の再読み込み',
      message: '一覧を取得し直します。よろしいですか？',
    );
    if (!confirmed) return;

    await _runLoad(_viewModel.load());
  }

  /// 「新規登録」。
  ///
  /// `go` ではなく `push` で登録画面を積むため、この画面は破棄されずに残る。
  /// 戻り値が `true`（登録した、または登録できたか分からない）のときだけ一覧を
  /// 取り直す。入力を破棄して戻った場合は `null` が返るため、取り直さない。
  ///
  /// 取り直しには `load()` を使う。「削除済みも表示」とページ番号は維持され、
  /// 行の選択だけが解除される。
  Future<void> _onCreate() async {
    final registered = await context.push<bool>('/users/new');
    if (!mounted || registered != true) return;

    await _runLoad(_viewModel.load());
  }

  /// 「編集」。
  ///
  /// 「新規登録」と同じく `push` で積むため、この画面は破棄されずに残る。戻り値の
  /// 扱いだけが登録と違う。
  ///
  /// - `null`（「戻る」で離脱した・取得に失敗して閉じた）— 何もしない。一覧の
  ///   表示も行の選択もそのまま残る
  /// - [UserEditUpdated] — その 1 行だけを差し替える。通信は発生せず、ページ・
  ///   「削除済みも表示」・行の選択はすべて維持される
  /// - [UserEditReloadNeeded]（404・成否不明）— 手元の一覧が実態とずれている
  ///   ことが確定しているため取り直す。このときだけ行の選択が外れる
  Future<void> _onEdit() async {
    final target = ref.read(usersViewModelProvider).selectedUser;
    if (target == null) return;

    final result = await context.push<UserEditResult>(
      '/users/${target.id}/edit',
    );
    if (!mounted || result == null) return;

    switch (result) {
      case UserEditUpdated(:final user):
        _viewModel.replaceUser(user);

      case UserEditReloadNeeded():
        await _runLoad(_viewModel.load());
    }
  }

  /// 「パスワードリセット」。
  ///
  /// 「新規登録」「編集」と同じく `push` で積むが、**戻り値を受け取らない**点だけ
  /// が違う。この画面は成否不明のときに画面へ留まる仕様のため、離脱そのものが
  /// 一覧への指示になる。`context.pop` の戻り値ではブラウザの戻るボタンを通る
  /// 経路を拾えないため、一覧への反映は `router.dart` の `onExit` が行う
  /// （ADR 0010）。そこから `replaceUser` と `load` が呼ばれる。
  Future<void> _onResetPassword() async {
    final target = ref.read(usersViewModelProvider).selectedUser;
    if (target == null) return;

    await context.push('/users/${target.id}/password');
  }

  /// 「削除」。
  ///
  /// 「編集」と同じく `push` で積み、戻り値を受け取って一覧へ反映する。削除画面は
  /// 成功・404・成否不明のいずれでも自分で `pop` を呼ぶため、値を渡せない経路
  /// （ブラウザの戻るボタンだけで離脱する）が存在せず、パスワードリセット画面の
  /// ように `onExit` へ寄せる必要がない。
  ///
  /// - `null`（「戻る」で離脱した・取得に通信エラー等で失敗して閉じた）— 何も
  ///   しない。一覧の表示も行の選択もそのまま残る
  /// - [UserDeleteDeleted] — 「削除済みも表示」がオンならその 1 行だけを削除後の
  ///   ユーザーで差し替える（行の選択・ページ・表示条件はすべて維持され、削除日時
  ///   と更新日時が入った表示になる）。オフのときは一覧からその行が消えるため
  ///   取り直す（表示ページは維持され、行の選択だけが外れる）
  /// - [UserDeleteReloadNeeded]（404・成否不明）— 一覧が実態とずれている可能性が
  ///   あるため取り直す
  Future<void> _onDelete() async {
    final target = ref.read(usersViewModelProvider).selectedUser;
    if (target == null) return;

    final result = await context.push<UserDeleteResult>(
      '/users/${target.id}/delete',
    );
    if (!mounted || result == null) return;

    switch (result) {
      case UserDeleteDeleted(:final user):
        if (ref.read(usersViewModelProvider).includeDeleted) {
          _viewModel.replaceUser(user);
        } else {
          await _runLoad(_viewModel.load());
        }

      case UserDeleteReloadNeeded():
        await _runLoad(_viewModel.load());
    }
  }

  /// ページ送り。
  Future<void> _onPageChanged(int page) async {
    await _runLoad(_viewModel.goToPage(page));
  }

  /// 「削除済みも表示」の切り替え。
  ///
  /// 「いいえ」を選んだ場合は状態を変えないため、スイッチは次の描画で操作前の
  /// 位置へ戻る。
  Future<void> _onIncludeDeletedChanged({required bool includeDeleted}) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '表示の切り替え',
      message: includeDeleted
          ? '削除済みのユーザーも表示します。一覧を取得し直します。よろしいですか？'
          : '削除済みのユーザーを表示から外します。一覧を取得し直します。よろしいですか？',
    );
    if (!confirmed) return;

    await _runLoad(_viewModel.setIncludeDeleted(includeDeleted: includeDeleted));
  }

  /// 「アカウントロック解除」。
  ///
  /// 押す直前に対象の名前を出すことが、誤操作の最後の歯止めになる。
  Future<void> _onUnlock() async {
    final target = ref.read(usersViewModelProvider).selectedUser;
    if (target == null) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'アカウントロックの解除',
      message: '${target.name} のアカウントロックを解除します。よろしいですか？',
    );
    if (!confirmed) return;

    final failure = await _viewModel.unlockSelected();
    if (!mounted) return;

    if (failure == null) {
      await showAlertDialog(
        context,
        title: '解除しました',
        message: '${target.name} のアカウントロックを解除しました。',
      );
    } else {
      await showAlertDialog(
        context,
        title: '解除に失敗しました',
        message: _failureMessage(failure),
      );
    }
  }

  /// 一覧の取得を実行し、失敗したらアラートを出す。
  Future<void> _runLoad(Future<UserFailure?> load) async {
    final failure = await load;
    if (!mounted || failure == null) return;

    await showAlertDialog(
      context,
      title: '取得に失敗しました',
      message: _failureMessage(failure),
    );
  }

  /// 失敗の内訳を画面の文言へ変換する。
  ///
  /// 「サーバーに届いていない」のか「API が不具合を返した」のかを切り分けられる
  /// ようにするため、疎通確認画面と同じく内訳まで出し分ける。
  String _failureMessage(UserFailure failure) => switch (failure) {
    UserNetworkFailure() => 'サーバーに接続できませんでした。コンテナが起動しているか確認してください。',
    UserApiFailure(:final message) => message,
    UserFormatFailure() => 'サーバーの応答を解釈できませんでした。',
  };
}
