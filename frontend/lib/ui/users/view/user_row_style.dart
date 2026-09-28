import 'package:flutter/material.dart';

import '../../../domain/models/user.dart';

/// 一覧の 1 行の配色。
class UserRowStyle {
  const UserRowStyle({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

/// 行の状態から配色を決める。
///
/// 状態は重なりうる（削除済みかつロック中、選択中かつ削除済みなど）ため、
/// **選択中 > 削除済み > ロック中 > 通常** の優先順位で 1 つだけを採る。色を混ぜ
/// ないのは、中間色が濁って区別できなくなるためで、選択中の行がロック中なのか
/// 削除済みなのかは「ロック状態」列・「削除日時」列とボタンの活性から分かる。
///
/// 削除済みをロック中より優先するのは、削除済みの行ではすべてのボタンが無効に
/// なり、そちらのほうが操作に直結するため。
UserRowStyle userRowStyle({required User user, required bool selected}) {
  if (selected) {
    return const UserRowStyle(
      background: Color(0xFFBBDEFB),
      foreground: Color(0xFF1F1F1F),
    );
  }
  if (user.isDeleted) {
    return const UserRowStyle(
      background: Color(0xFFF5F5F5),
      foreground: Color(0xFF616161),
    );
  }
  if (user.isLocked) {
    return const UserRowStyle(
      background: Color(0xFFFFEBEE),
      foreground: Color(0xFF1F1F1F),
    );
  }
  return const UserRowStyle(
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF1F1F1F),
  );
}
