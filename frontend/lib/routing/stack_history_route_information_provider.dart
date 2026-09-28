import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'browser_history.dart';

/// スタックに積んだ画面を閉じたときに、ブラウザの履歴を増やさず 1 つ戻す
/// RouteInformationProvider。
///
/// go_router の RouteInformationProvider を包み、ルーターが履歴を記録する
/// [routerReportsNewRouteInformation] だけを差し替える。それ以外はすべて包んだ
/// provider にそのまま任せる。
///
/// **なぜ必要か。** go_router は、`context.push` で積んだ画面を閉じたときも、閉じた
/// 後の状態を新しい記録としてブラウザの履歴に追加する。そのため、新規登録画面を
/// 閉じてユーザー一覧に戻った後にブラウザの戻るを押すと、閉じたはずの新規登録画面
/// が再び表示される。
///
/// **どうするか。** 「URL が同じで、スタックに積んだ画面の数が減った」記録（＝積んだ
/// 画面を閉じた）が来たら、新しい記録を追加せず、ブラウザの履歴を 1 つ戻す。開いた
/// ときに追加した記録が取り消され、閉じた後のブラウザの戻るは、一覧を開く前の画面
/// （ホーム画面など）へ戻る。積むときは、これまでどおり記録を 1 つ追加するため、
/// 積んだ画面を開いている間のブラウザの戻るは、積む前の画面（ユーザー一覧など）へ
/// 戻る。
///
/// 判定は記録の内容（積んだ画面の数）で行う。閉じる前に確認ダイアログ（`onExit`）
/// を挟み、「はい」を待ってから画面が閉じる場合も、閉じた時点の記録で判定される。
class StackHistoryRouteInformationProvider extends RouteInformationProvider {
  StackHistoryRouteInformationProvider(this._inner) {
    _inner.addListener(_onInnerChanged);
  }

  final RouteInformationProvider _inner;

  /// ブラウザの履歴にある、今の記録。分からないときは `null`。
  ///
  /// ルーターが記録したとき（[routerReportsNewRouteInformation]）と、ブラウザの
  /// 戻る・進むで記録が切り替わったとき（[_onInnerChanged]）に更新する。
  RouteInformation? _current;

  @override
  RouteInformation get value => _inner.value;

  @override
  void addListener(VoidCallback listener) => _inner.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _inner.removeListener(listener);

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    final current = _current;
    if (type != RouteInformationReportingType.navigate &&
        current != null &&
        _sameLocation(routeInformation.uri, current.uri) &&
        _stackedCount(routeInformation.state) <
            _stackedCount(current.state)) {
      // 積んだ画面を閉じた。開いたときに追加した記録を取り消す。ブラウザが 1 つ前の
      // 記録へ戻ると、その記録が go_router に届き、[_onInnerChanged] で _current も
      // 更新される。
      _current = null;
      browserHistoryBack();
      return;
    }

    _inner.routerReportsNewRouteInformation(routeInformation, type: type);
    _current = routeInformation;
  }

  /// ブラウザの戻る・進むで記録が切り替わったときに、今の記録を覚え直す。
  ///
  /// go_router の provider は、ブラウザから届いた記録を、状態を持つ形（go_router が
  /// 記録した形）のまま値にする。`context.push` などアプリの操作で値が変わったとき
  /// は別の形の状態になるため、それは覚えない（ルーターの記録で覚える）。
  void _onInnerChanged() {
    final value = _inner.value;
    if (value.state is Map) _current = value;
  }

  /// パスとクエリが同じか。
  static bool _sameLocation(Uri a, Uri b) =>
      a.path == b.path && mapEquals(a.queryParameters, b.queryParameters);

  /// 記録の中で、スタックに積んだ画面の数。
  ///
  /// go_router は、`context.push` で積んだ画面を `imperativeMatches` として記録の
  /// 状態に入れる。
  static int _stackedCount(Object? state) {
    if (state is Map) {
      final matches = state['imperativeMatches'];
      if (matches is List) return matches.length;
    }
    return 0;
  }
}
