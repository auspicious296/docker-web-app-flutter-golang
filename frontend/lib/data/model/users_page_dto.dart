import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_dto.dart';

part 'users_page_dto.freezed.dart';
part 'users_page_dto.g.dart';

/// `GET /api/users` のレスポンス（DTO）。
///
/// 一覧は裸の配列ではなくオブジェクトで包まれている
/// （`{"users":[...],"page":1,"per_page":20,"total":137}`）。
/// `total_pages` は含まれないため、総ページ数はドメインモデル側で算出する。
@freezed
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class UsersPageDto with _$UsersPageDto {
  const UsersPageDto({
    required this.users,
    required this.page,
    required this.perPage,
    required this.total,
  });

  factory UsersPageDto.fromJson(Map<String, Object?> json) =>
      _$UsersPageDtoFromJson(json);

  final List<UserDto> users;
  final int page;
  final int perPage;
  final int total;
}
