import 'package:freezed_annotation/freezed_annotation.dart';

part 'csrf_token_dto.freezed.dart';
part 'csrf_token_dto.g.dart';

/// `GET /api/csrf-token` のレスポンス（DTO）。`{"csrf_token":"..."}`。
@freezed
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class CsrfTokenDto with _$CsrfTokenDto {
  const CsrfTokenDto({required this.csrfToken});

  factory CsrfTokenDto.fromJson(Map<String, Object?> json) =>
      _$CsrfTokenDtoFromJson(json);

  final String csrfToken;
}
