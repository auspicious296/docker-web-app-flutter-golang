import 'package:freezed_annotation/freezed_annotation.dart';

part 'health_status.freezed.dart';

/// API の稼働状態を表すドメインモデル。
///
/// API のレスポンス（DTO）である [HealthResponse] とは別に定義し、
/// Repository で変換してから ViewModel へ渡す。API のレスポンス形式が
/// 変わっても、画面側はこのモデルだけを見ていればよい状態を保つため。
@freezed
class HealthStatus with _$HealthStatus {
  const HealthStatus({required this.status});

  /// 稼働状態を表す文字列（例：`ok`）。
  final String status;
}
