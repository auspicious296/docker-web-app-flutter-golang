import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../view_model/session_view_model.dart';
import 'logout_flow.dart';

/// メニューの項目。
enum _UserMenuItem { passwordChange, logout }

/// タイトルバーの右端に置く「ユーザー名」ボタン（ADR 0015）。
///
/// タップするとメニューを開く。マイページでは「パスワード変更」「ログアウト」、
/// パスワード変更画面では「ログアウト」だけを出す（[showPasswordChange]）。
///
/// 幅はユーザー名の長さに応じて広がり、[_maxWidth] で止まって末尾を省略する。
/// 省略されたときも、カーソルを載せるか長押しすると全文が読める。
///
/// ログイン中のユーザーが分からないあいだ（取得の前・ログアウトの後）は表示しない。
class UserMenuButton extends ConsumerWidget {
  const UserMenuButton({super.key, this.showPasswordChange = true});

  /// メニューに「パスワード変更」を出すか。
  final bool showPasswordChange;

  /// ボタンの最大幅。全角で約 15 文字。
  static const double _maxWidth = 240;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionViewModelProvider.select((s) => s.user));
    if (user == null) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.primary;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: PopupMenuButton<_UserMenuItem>(
        tooltip: user.name,
        position: PopupMenuPosition.under,
        // メニューの処理は、このボタンの外側の context で行う。ログアウトすると
        // ボタン自体が消える（PopupMenuButton の context は破棄される）ため。
        onSelected: (item) => _onSelected(context, item, user.email),
        itemBuilder: (_) => [
          if (showPasswordChange)
            const PopupMenuItem(
              value: _UserMenuItem.passwordChange,
              child: Text('パスワード変更'),
            ),
          const PopupMenuItem(
            value: _UserMenuItem.logout,
            child: Text('ログアウト'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_circle, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: color),
                ),
              ),
              Icon(Icons.arrow_drop_down, color: color),
            ],
          ),
        ),
      ),
    );
  }

  /// [email] はログイン中のユーザーのメールアドレス。ログアウトするとユーザーの
  /// 情報は消えるため、メニューを開いた時点の値を受け取っておく。
  Future<void> _onSelected(
    BuildContext context,
    _UserMenuItem item,
    String email,
  ) async {
    switch (item) {
      case _UserMenuItem.passwordChange:
        // マイページの上に積む。URL はマイページと同じ /me のまま（ADR 0015）。
        await context.push('/me/password');

      case _UserMenuItem.logout:
        final result = await confirmAndLogout(context);
        if (!context.mounted) return;
        // メニューからのログアウトは、成功しても切れていても、ログイン画面へ移る。
        // ログインしていたユーザーのメールアドレスを入力欄に入れておく。
        if (result != LogoutFlowResult.stayed) {
          context.go('/login', extra: email);
        }
    }
  }
}
