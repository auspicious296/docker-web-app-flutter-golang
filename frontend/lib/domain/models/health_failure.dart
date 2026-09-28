import 'package:freezed_annotation/freezed_annotation.dart';

part 'health_failure.freezed.dart';

/// API の呼び出しに失敗した理由。
///
/// `/api/health` は「画面 → nginx → Go API の経路が繋がっているか」を確認する
/// ためのエンドポイントなので、単に「失敗した」ではなく、どこで失敗したのかを
/// 区別できるようにしている。Service が投げ、ViewModel が受け取る。
@freezed
sealed class HealthFailure with _$HealthFailure implements Exception {
  /// API から応答が返ってこなかった（コンテナが起動していない、nginx の
  /// 転送設定が誤っているなど）。
  const factory HealthFailure.network() = HealthNetworkFailure;

  /// API は応答したが、ステータスコードが 200 以外だった。
  const factory HealthFailure.httpStatus(int statusCode) =
      HealthHttpStatusFailure;

  /// 応答は得られたが、期待する JSON の形式ではなかった。
  const factory HealthFailure.format() = HealthFormatFailure;
}
