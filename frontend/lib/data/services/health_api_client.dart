import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../config/api_config.dart';
import '../../domain/models/health_failure.dart';
import '../model/health_response.dart';

part 'health_api_client.g.dart';

/// `/api/health` を呼び出す API クライアント（Service 層）。
///
/// エンドポイントのパスはこのクラスが持つ。`lib/config/` に置くのは
/// ベース URL だけで、パスは呼び出す Service の隣に置く方針。
class HealthApiClient {
  const HealthApiClient({required this.client});

  final http.Client client;

  /// API の稼働状態を取得する。
  ///
  /// 失敗した場合は [HealthFailure] を投げる。どこで失敗したのかを画面で
  /// 切り分けられるよう、通信・HTTP ステータス・応答形式の 3 つに分ける。
  Future<HealthResponse> fetchHealth() async {
    final http.Response response;
    try {
      response = await client.get(Uri.parse('$apiBaseUrl/api/health'));
    } on Exception {
      // API まで到達できなかった（コンテナ未起動、nginx の転送設定の誤りなど）
      throw const HealthFailure.network();
    }

    if (response.statusCode != 200) {
      throw HealthFailure.httpStatus(response.statusCode);
    }

    try {
      final json = jsonDecode(response.body) as Map<String, Object?>;
      return HealthResponse.fromJson(json);
    } on Object {
      // JSON として壊れている場合（FormatException）と、
      // 形は JSON でもキーや型が想定と違う場合（TypeError）の両方を含む
      throw const HealthFailure.format();
    }
  }
}

@riverpod
HealthApiClient healthApiClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return HealthApiClient(client: client);
}
