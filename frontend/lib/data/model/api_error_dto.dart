import 'package:freezed_annotation/freezed_annotation.dart';

part 'api_error_dto.freezed.dart';
part 'api_error_dto.g.dart';

/// API が失敗時に返す JSON（DTO）。
///
/// `/api/` 配下は失敗時に必ず `{"error":{"code":"...","message":"..."}}` を返す
/// （標準の ServeMux が返す 404 / 405 もラッパーで JSON に揃えられている）。
@freezed
@JsonSerializable(createToJson: false)
class ApiErrorDto with _$ApiErrorDto {
  const ApiErrorDto({required this.error});

  factory ApiErrorDto.fromJson(Map<String, Object?> json) =>
      _$ApiErrorDtoFromJson(json);

  final ApiErrorBodyDto error;
}

/// [ApiErrorDto] の `error` の中身。
@freezed
@JsonSerializable(createToJson: false)
class ApiErrorBodyDto with _$ApiErrorBodyDto {
  const ApiErrorBodyDto({
    required this.code,
    required this.message,
    this.fields = const [],
  });

  factory ApiErrorBodyDto.fromJson(Map<String, Object?> json) =>
      _$ApiErrorBodyDtoFromJson(json);

  /// 機械判別用のコード（`not_found` / `validation_error` など）。
  final String code;

  /// 画面にそのまま表示できる日本語のメッセージ。
  final String message;

  /// どの入力項目がどう不正かの内訳。
  ///
  /// 検証エラー（`validation_error`）のときだけ JSON に現れるため、既定値を
  /// 空のリストにしている。登録画面は、この内訳を各入力欄の直下に表示する。
  final List<ApiFieldErrorDto> fields;
}

/// [ApiErrorBodyDto] の `fields` の要素。
@freezed
@JsonSerializable(createToJson: false)
class ApiFieldErrorDto with _$ApiFieldErrorDto {
  const ApiFieldErrorDto({required this.field, required this.message});

  factory ApiFieldErrorDto.fromJson(Map<String, Object?> json) =>
      _$ApiFieldErrorDtoFromJson(json);

  /// 項目の名前（`name` / `email` / `password`）。
  final String field;

  /// その項目に対する日本語のメッセージ。
  final String message;
}
