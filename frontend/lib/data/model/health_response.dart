import 'package:freezed_annotation/freezed_annotation.dart';

part 'health_response.freezed.dart';
part 'health_response.g.dart';

/// `GET /api/health` のレスポンス（DTO）。
///
/// API が返す JSON（`{"status":"ok"}`）と 1 対 1 に対応する。
/// 画面へはこのままではなく、Repository でドメインモデルへ変換してから渡す。
@freezed
@JsonSerializable(createToJson: false)
class HealthResponse with _$HealthResponse {
  const HealthResponse({required this.status});

  factory HealthResponse.fromJson(Map<String, Object?> json) =>
      _$HealthResponseFromJson(json);

  final String status;
}
