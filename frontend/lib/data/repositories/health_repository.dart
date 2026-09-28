import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/health_status.dart';
import '../services/health_api_client.dart';

part 'health_repository.g.dart';

/// API の稼働状態を供給する Repository。
///
/// ここでは Service を呼んで DTO をドメインモデルへ変換するだけで、
/// キャッシュや複数データソースの統合といった処理は持たない（素通しに近い）。
/// それでも層を置いているのは、README が定める
/// `View → ViewModel → Repository → Service` の 4 層を、最小の題材である
/// `/api/health` で一度通して示すため。ユーザー CRUD 以降も同じ形が続く。
class HealthRepository {
  const HealthRepository({required this.apiClient});

  final HealthApiClient apiClient;

  /// API の稼働状態を取得する。失敗した場合は `HealthFailure` を投げる。
  Future<HealthStatus> fetchHealthStatus() async {
    final response = await apiClient.fetchHealth();
    return HealthStatus(status: response.status);
  }
}

@riverpod
HealthRepository healthRepository(Ref ref) =>
    HealthRepository(apiClient: ref.watch(healthApiClientProvider));
