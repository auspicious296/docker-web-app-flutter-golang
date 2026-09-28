import 'package:freezed_annotation/freezed_annotation.dart';

part 'current_user.freezed.dart';

/// ログイン中のユーザー（`GET /api/me` の結果）。
///
/// 管理者向けの `User` とは別の型にしている。API が返すのは本人に必要な 3 項目
/// だけで（ADR 0014）、ロックや削除の状態を持たないためである。
@freezed
class CurrentUser with _$CurrentUser {
  const CurrentUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final int id;
  final String name;
  final String email;
}
