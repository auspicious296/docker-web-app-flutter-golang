import 'package:freezed_annotation/freezed_annotation.dart';

import 'user.dart';

part 'users_page.freezed.dart';

/// ユーザー一覧の 1 ページ分。
///
/// Repository が返す取得結果そのもの。ページ送りの判定（総ページ数・先頭／最終
/// ページか）は、画面の状態を持つ `UsersState` 側に置いている。API は
/// `total_pages` を返さないため、総ページ数は [total] と [perPage] から算出する。
@freezed
class UsersPage with _$UsersPage {
  const UsersPage({
    required this.users,
    required this.page,
    required this.perPage,
    required this.total,
  });

  /// このページに含まれるユーザー。並び順は登録順（API 側で `ORDER BY id`）。
  final List<User> users;

  /// 現在のページ番号（1 起点）。
  final int page;

  /// 1 ページあたりの行数。
  final int perPage;

  /// 条件に一致するユーザーの総数（このページの件数ではない）。
  final int total;
}
