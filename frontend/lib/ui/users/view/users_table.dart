import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/user.dart';
import '../../core/content_width.dart';
import '../../core/date_format.dart';
import 'user_row_style.dart';

/// ユーザー一覧のテーブル。
///
/// ヘッダー行と左端の「ユーザー名」列を固定し、幅が足りなければ縦横のスクロール
/// で対応する。列の並び替えと絞り込みは持たない。
class UsersTable extends StatelessWidget {
  const UsersTable({
    super.key,
    required this.users,
    required this.selectedUserId,
    required this.onRowTap,
  });

  final List<User> users;
  final int? selectedUserId;

  /// 行がタップされたときに呼ばれる。同じ行の再タップは呼び出し側で解除に使う。
  final void Function(int userId) onRowTap;

  @override
  Widget build(BuildContext context) {
    return DataTable2(
      // ヘッダー行（1 行目）と左端の 1 列を固定する
      fixedTopRows: 1,
      fixedLeftColumns: 1,
      // チェックボックス列は出さず、行のタップで選択する
      showCheckboxColumn: false,
      // テーブルがこれ以上狭くならない幅。ウインドウがこれを下回ると、テーブル内
      // に横スクロールが出る。1,366px のディスプレイで全列が収まる値。
      minWidth: kMinContentWidth,
      horizontalMargin: 16,
      // 列幅には影響せず、セルの内側の余白としてだけ効く
      columnSpacing: 24,
      dataRowHeight: 56,
      headingRowHeight: 56,
      headingRowColor: const WidgetStatePropertyAll(Color(0xFF0047AB)),
      headingTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      border: TableBorder.all(color: const Color(0xFFE0E0E0)),
      empty: const Center(child: Text('該当するユーザーがいません')),
      columns: _columns,
      rows: [for (final user in users) _buildRow(user)],
    );
  }

  /// 列の定義。
  ///
  /// ヘッダーのラベルは折り返らず、幅が足りないと省略記号も出ずに切れるため、
  /// どの列もラベルが収まる幅を確保してある（最長は「ログイン失敗回数」の 8 文字）。
  /// 幅を変えられるのは、実データが幅を超えうる 2 列だけ。`minWidth` を初期幅より
  /// 小さくすることで、広げるだけでなく縮めることもできる。
  static const List<DataColumn2> _columns = [
    DataColumn2(
      label: Text('ユーザー名'),
      fixedWidth: 180,
      minWidth: 180,
      isResizable: true,
    ),
    // この列だけ固定幅を持たない（可変列）。テーブルが与えられた幅ぴったりに
    // 広がり、余った幅をこの列が吸収する。可変列が 1 つもないと、テーブルは
    // 列幅の合計までしか広がらず、固定した左端の列とのあいだに隙間が開く。
    DataColumn2(
      label: Text('メールアドレス'),
      minWidth: 240,
      isResizable: true,
    ),
    DataColumn2(label: Text('作成日時'), fixedWidth: 160),
    DataColumn2(label: Text('更新日時'), fixedWidth: 160),
    DataColumn2(label: Text('削除日時'), fixedWidth: 160),
    DataColumn2(label: Text('ロック状態'), fixedWidth: 110),
    DataColumn2(label: Text('ロック日時'), fixedWidth: 160),
    DataColumn2(label: Text('ログイン失敗回数'), fixedWidth: 140, numeric: true),
    DataColumn2(label: Text('最終ログイン日時'), fixedWidth: 160),
  ];

  DataRow2 _buildRow(User user) {
    final selected = user.id == selectedUserId;
    final style = userRowStyle(user: user, selected: selected);

    return DataRow2(
      key: ValueKey(user.id),
      selected: selected,
      onSelectChanged: (_) => onRowTap(user.id),
      // 背景色は color ではなく decoration で渡す。color は左端の固定列に届かず、
      // ロック中の行の左端だけが白く抜けてしまうため。
      decoration: BoxDecoration(color: style.background),
      cells: [
        _cell(user.name, style),
        _cell(user.email, style),
        _cell(formatDateTime(user.createdAt), style),
        _cell(formatDateTime(user.updatedAt), style),
        _cell(formatDateTime(user.deletedAt), style),
        _cell(user.isLocked ? 'ロック中' : '', style),
        _cell(formatDateTime(user.lockedAt), style),
        _cell('${user.failedLoginAttempts}', style),
        _cell(formatDateTime(user.lastLoginAt), style),
      ],
    );
  }

  /// セルを組み立てる。
  ///
  /// 幅に収まらない文字は末尾を省略記号にし、全文はカーソルを載せるか長押しする
  /// と読める。一部の列にだけツールチップを付けると、押した列によって行が選択
  /// されたりされなかったりするため、**9 列すべてに付ける**。
  DataCell _cell(String text, UserRowStyle style) => DataCell(
    Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: style.foreground),
      ),
    ),
  );
}
