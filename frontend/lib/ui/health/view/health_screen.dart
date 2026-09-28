import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../domain/models/health_failure.dart';
import '../../core/back_app_bar.dart';
import '../view_model/health_view_model.dart';

/// 疎通確認画面。
///
/// ボタンを押すと `/api/health` を呼び出し、その上に結果を表示する。
/// 画面 → nginx → Go API の経路が繋がっているかを確認するための画面。
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(healthViewModelProvider);

    return Scaffold(
      appBar: const BackAppBar(title: 'API 疎通テスト'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _HealthResult(state: state),
              const SizedBox(height: 24),
              FilledButton(
                // 通信中はボタンを無効化する
                onPressed: state is HealthLoading
                    ? null
                    : () => ref
                          .read(healthViewModelProvider.notifier)
                          .fetchHealth(),
                child: const Text('API を呼び出す'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 状態に応じた結果表示。4 つの状態をすべて網羅する。
class _HealthResult extends StatelessWidget {
  const _HealthResult({required this.state});

  final HealthState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      HealthInitial() => const Text('ボタンを押すと /api/health を呼び出します'),
      HealthLoading() => const CircularProgressIndicator(),
      HealthSuccess(:final status) => Text(
        'status: ${status.status}',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      HealthFailureState(:final failure) => Column(
        children: [
          Text(
            '取得に失敗しました',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(_failureMessage(failure)),
        ],
      ),
    };
  }

  /// 失敗の内訳を画面の文言へ変換する。
  ///
  /// 単に「失敗した」だけでは、コンテナが起動していないのか nginx の転送設定が
  /// 誤っているのかを画面から切り分けられないため、内訳まで表示する。
  String _failureMessage(HealthFailure failure) => switch (failure) {
    HealthNetworkFailure() => 'API から応答がありません（通信エラー）',
    HealthHttpStatusFailure(:final statusCode) =>
      'API がエラーを返しました（HTTP $statusCode）',
    HealthFormatFailure() => '応答の形式が不正です',
  };
}
