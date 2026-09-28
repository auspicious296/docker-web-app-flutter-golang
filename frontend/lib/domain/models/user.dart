import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';

/// 管理対象のユーザーを表すドメインモデル。
///
/// API のレスポンス（DTO）である `UserDto` とは別に定義し、Repository で変換して
/// から ViewModel へ渡す。DTO では日時が文字列のままなので、ここで [DateTime] に
/// してある。パスワードのハッシュは API が返さないため、この型にも存在しない。
@freezed
class User with _$User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.isLocked,
    required this.lockedAt,
    required this.failedLoginAttempts,
    required this.lastLoginAt,
  });

  final int id;

  /// 表示名（姓名をまとめて 1 つの値として持つ）。
  final String name;

  /// メールアドレス。第二段階ではログイン ID として使う。
  final String email;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 論理削除された日時。削除されていなければ `null`。
  final DateTime? deletedAt;

  /// アカウントがロックされているか。
  final bool isLocked;

  /// 最後にロックがかかった日時。
  ///
  /// 解除しても `null` には戻さないため、[isLocked] が `false` でここに日時が
  /// 入っている状態は「過去にロックされたが解除済み」を表す正常な状態。
  final DateTime? lockedAt;

  /// 連続してログインに失敗した回数。第一段階では常に 0 が返る。
  final int failedLoginAttempts;

  /// 最終ログイン日時（ADR 0015）。一度もログインしていなければ `null`。
  final DateTime? lastLoginAt;

  /// 論理削除されているか。
  ///
  /// 一覧画面では、行の背景色・ボタンの活性・「削除日時」列の 3 か所でこの判定を
  /// 使う。`deletedAt != null` を各所に散らさないため、ここに集約している。
  bool get isDeleted => deletedAt != null;
}
