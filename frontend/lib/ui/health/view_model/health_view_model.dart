import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/health_repository.dart';
import '../../../domain/models/health_failure.dart';
import '../../../domain/models/health_status.dart';

part 'health_view_model.freezed.dart';
part 'health_view_model.g.dart';

/// 疎通確認画面の状態。
///
/// ボタンを押して初めて通信が始まるため、`AsyncValue` の 3 状態
/// （loading / data / error）では「まだ押していない」を表せない。
/// そのため 4 状態を sealed class として自前で定義している。
@freezed
sealed class HealthState with _$HealthState {
  /// まだボタンが押されていない。
  const factory HealthState.initial() = HealthInitial;

  /// API の応答を待っている。
  const factory HealthState.loading() = HealthLoading;

  /// API の稼働状態を取得できた。
  const factory HealthState.success(HealthStatus status) = HealthSuccess;

  /// API の呼び出しに失敗した。
  const factory HealthState.failure(HealthFailure failure) = HealthFailureState;
}

/// 疎通確認画面の ViewModel。
@riverpod
class HealthViewModel extends _$HealthViewModel {
  /// 依存する Repository。
  ///
  /// メソッドの中で `ref.read` せず、`build` で `ref.watch` して保持する。
  /// `ref.read` は provider を監視しないため、コード生成の provider（既定で
  /// 自動破棄）は誰にも監視されないまま生成され、`await` でイベントループに
  /// 制御が戻った時点で破棄されてしまう。破棄されると Service が持つ
  /// `http.Client` が `close()` され、通信中のリクエストが中断される。
  late final HealthRepository _repository;

  @override
  HealthState build() {
    _repository = ref.watch(healthRepositoryProvider);
    return const HealthState.initial();
  }

  /// `/api/health` を呼び出し、結果を状態に反映する。
  ///
  /// すでに通信中の場合は何もしない（ボタンの連打で多重に呼ばないため）。
  Future<void> fetchHealth() async {
    if (state is HealthLoading) return;

    state = const HealthState.loading();
    try {
      final status = await _repository.fetchHealthStatus();
      state = HealthState.success(status);
    } on HealthFailure catch (failure) {
      state = HealthState.failure(failure);
    }
  }
}
