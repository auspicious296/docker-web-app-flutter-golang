import 'package:flutter/material.dart';

import '../view_model/users_view_model.dart';

/// テーブルの直上に並ぶ操作ボタン群。
///
/// 左はユーザーに対する操作、右は一覧の表示に対する操作で、性質が違うため群を
/// 分けている。幅が足りなくなると**群の単位で 2 段に折り返し**、右の群がまるごと
/// 2 段目の左寄せへ移る。それでも左の群が収まらない場合は、内側でボタン単位に
/// 折り返す。
class UsersActionBar extends StatelessWidget {
  const UsersActionBar({
    super.key,
    required this.state,
    required this.onReload,
    required this.onCreate,
    required this.onEdit,
    required this.onResetPassword,
    required this.onDelete,
    required this.onUnlock,
    required this.onIncludeDeletedChanged,
  });

  final UsersState state;
  final VoidCallback onReload;
  final VoidCallback onCreate;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;
  final VoidCallback onUnlock;
  final void Function({required bool includeDeleted}) onIncludeDeletedChanged;

  @override
  Widget build(BuildContext context) {
    // 子が 1 段に収まるときは左右へ分かれ、2 段になると各段とも左寄せになる
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 8,
      children: [_userActions(context), _viewActions(context)],
    );
  }

  /// 左の群：選択したユーザーに対する操作。
  Widget _userActions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          style: _filledStyle(context, const Color(0xFF0277BD)),
          onPressed: state.canCreate ? onCreate : null,
          child: const Text('新規登録'),
        ),
        FilledButton(
          style: _filledStyle(context, const Color(0xFF0277BD)),
          onPressed: state.canOperateSelected ? onEdit : null,
          child: const Text('編集'),
        ),
        FilledButton(
          style: _filledStyle(context, const Color(0xFF0277BD)),
          onPressed: state.canOperateSelected ? onResetPassword : null,
          child: const Text('パスワードリセット'),
        ),
        FilledButton(
          style: _filledStyle(context, const Color(0xFFD32F2F)),
          onPressed: state.canOperateSelected ? onDelete : null,
          child: const Text('削除'),
        ),
        FilledButton(
          // この 1 つだけ画面遷移せずその場で実行されるため、色を分けている
          style: _filledStyle(context, const Color(0xFF2E7D32)),
          onPressed: state.canUnlock ? onUnlock : null,
          child: const Text('アカウントロック解除'),
        ),
      ],
    );
  }

  /// 右の群：一覧の表示に対する操作。
  Widget _viewActions(BuildContext context) {
    // 取得に失敗している間は、復帰の手段である「一覧再読み込み」だけを残す
    final failed = state.loadFailure != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0277BD),
            side: const BorderSide(color: Color(0xFF0277BD)),
          ),
          onPressed: onReload,
          child: const Text('一覧再読み込み'),
        ),
        const SizedBox(width: 16),
        const Text('削除済みも表示'),
        Switch(
          value: state.includeDeleted,
          onChanged: failed
              ? null
              : (value) => onIncludeDeletedChanged(includeDeleted: value),
        ),
      ],
    );
  }

  /// 塗りつぶしボタンの配色。
  ///
  /// `backgroundColor` だけを指定すると無効時も同じ色のままになり、押せるかどうか
  /// が見分けられなくなるため、無効時の色も明示的に渡す（Material 既定のグレー）。
  ButtonStyle _filledStyle(BuildContext context, Color background) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: Colors.white,
      disabledBackgroundColor: onSurface.withValues(alpha: 0.12),
      disabledForegroundColor: onSurface.withValues(alpha: 0.38),
    );
  }
}
