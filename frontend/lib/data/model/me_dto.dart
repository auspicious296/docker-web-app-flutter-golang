import 'package:freezed_annotation/freezed_annotation.dart';

part 'me_dto.freezed.dart';
part 'me_dto.g.dart';

/// `GET /api/me` のレスポンス（DTO）。`{"id","name","email"}` の 3 項目（ADR 0014）。
@freezed
@JsonSerializable(createToJson: false)
class MeDto with _$MeDto {
  const MeDto({required this.id, required this.name, required this.email});

  factory MeDto.fromJson(Map<String, Object?> json) => _$MeDtoFromJson(json);

  final int id;
  final String name;
  final String email;
}
