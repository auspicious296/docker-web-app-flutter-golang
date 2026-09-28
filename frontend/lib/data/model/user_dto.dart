import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_dto.freezed.dart';
part 'user_dto.g.dart';

/// ユーザー 1 件の API レスポンス（DTO）。
///
/// API が返す JSON と 1 対 1 に対応する。キーは DB のカラム名と揃えた
/// `snake_case` のため、`fieldRename` で変換している。日時は RFC 3339 の文字列の
/// まま受け、[DateTime] への変換は Repository が行う。
/// `password_hash` は API が返さないため、この型にも存在しない。
@freezed
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class UserDto with _$UserDto {
  const UserDto({
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

  factory UserDto.fromJson(Map<String, Object?> json) =>
      _$UserDtoFromJson(json);

  final int id;
  final String name;
  final String email;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final bool isLocked;
  final String? lockedAt;
  final int failedLoginAttempts;
  final String? lastLoginAt;
}
