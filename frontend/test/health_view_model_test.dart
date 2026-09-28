import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/services/health_api_client.dart';
import 'package:frontend/domain/models/health_failure.dart';
import 'package:frontend/ui/health/view_model/health_view_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 破棄された provider を記録する観測者。
final class _DisposeObserver extends ProviderObserver {
  final List<String> disposed = [];

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    disposed.add(context.provider.name ?? context.provider.toString());
  }
}

/// API クライアントを差し替えた ProviderContainer を作る。
///
/// Service（HealthApiClient）と Repository は本物を通すため、
/// 失敗の内訳を振り分ける処理もあわせて検証できる。
///
/// `listen` しているのは、画面（View）が ViewModel を `watch` している状態を
/// 模すため。これがないと ViewModel が誰にも監視されず、自動破棄の対象になる。
ProviderContainer _createContainer(
  MockClient client, {
  _DisposeObserver? observer,
}) {
  final container = ProviderContainer(
    observers: [?observer],
    overrides: [
      healthApiClientProvider.overrideWithValue(
        HealthApiClient(client: client),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(healthViewModelProvider, (_, _) {});
  return container;
}

void main() {
  test('初期状態は未実行', () {
    final container = _createContainer(
      MockClient((_) async => http.Response('{"status":"ok"}', 200)),
    );

    expect(container.read(healthViewModelProvider), isA<HealthInitial>());
  });

  test('取得に成功すると status を保持した成功状態になる', () async {
    final container = _createContainer(
      MockClient((_) async => http.Response('{"status":"ok"}', 200)),
    );

    await container.read(healthViewModelProvider.notifier).fetchHealth();

    final state = container.read(healthViewModelProvider);
    expect(state, isA<HealthSuccess>());
    expect((state as HealthSuccess).status.status, 'ok');
  });

  test('API へ到達できない場合は通信エラーになる', () async {
    final container = _createContainer(
      MockClient((_) async => throw http.ClientException('接続できません')),
    );

    await container.read(healthViewModelProvider.notifier).fetchHealth();

    final state = container.read(healthViewModelProvider);
    expect(state, isA<HealthFailureState>());
    expect((state as HealthFailureState).failure, isA<HealthNetworkFailure>());
  });

  test('200 以外が返った場合はステータスコードを保持した失敗状態になる', () async {
    final container = _createContainer(
      MockClient((_) async => http.Response('Bad Gateway', 502)),
    );

    await container.read(healthViewModelProvider.notifier).fetchHealth();

    final state = container.read(healthViewModelProvider);
    expect(state, isA<HealthFailureState>());
    final failure = (state as HealthFailureState).failure;
    expect(failure, isA<HealthHttpStatusFailure>());
    expect((failure as HealthHttpStatusFailure).statusCode, 502);
  });

  test('JSON として解釈できない応答は形式エラーになる', () async {
    final container = _createContainer(
      MockClient((_) async => http.Response('ok', 200)),
    );

    await container.read(healthViewModelProvider.notifier).fetchHealth();

    final state = container.read(healthViewModelProvider);
    expect(state, isA<HealthFailureState>());
    expect((state as HealthFailureState).failure, isA<HealthFormatFailure>());
  });

  test('期待するキーがない応答は形式エラーになる', () async {
    final container = _createContainer(
      MockClient((_) async => http.Response('{"state":"ok"}', 200)),
    );

    await container.read(healthViewModelProvider.notifier).fetchHealth();

    final state = container.read(healthViewModelProvider);
    expect(state, isA<HealthFailureState>());
    expect((state as HealthFailureState).failure, isA<HealthFormatFailure>());
  });

  test('通信中にデータ層の provider が破棄されない', () async {
    // ViewModel が Repository を `ref.read` で取得していると、誰にも監視されない
    // まま生成されるため、通信中（await 中）に自動破棄される。破棄されると
    // Service の http.Client が close され、実行中のリクエストが中断されて
    // 通信エラーになる。それを防げていることを確認する。
    final completer = Completer<http.Response>();
    final observer = _DisposeObserver();
    final container = _createContainer(
      MockClient((_) => completer.future),
      observer: observer,
    );

    final request = container
        .read(healthViewModelProvider.notifier)
        .fetchHealth();

    // 通信中にイベントループへ制御を戻す
    await Future<void>.delayed(Duration.zero);

    expect(container.read(healthViewModelProvider), isA<HealthLoading>());
    expect(observer.disposed, isNot(contains('healthRepositoryProvider')));

    completer.complete(http.Response('{"status":"ok"}', 200));
    await request;

    expect(container.read(healthViewModelProvider), isA<HealthSuccess>());
  });
}
