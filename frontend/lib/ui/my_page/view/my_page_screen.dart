import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../domain/models/auth_failure.dart';
import '../../core/app_dialogs.dart';
import '../../core/back_app_bar.dart';
import '../../core/content_width.dart';
import '../../core/loading_overlay.dart';
import '../view_model/session_view_model.dart';
import 'user_menu_button.dart';

/// 情報を囲む箱の幅。登録画面・パスワードリセット画面と同じ値を使う。
///
/// 以下のレイアウト定数はいずれも既存の画面と揃えている。画面を行き来したときに
/// 箱とラベル列の位置が動かないようにするため。
const double _boxWidth = 720;

/// 箱の内側の余白。
const double _boxPadding = 32;

/// ラベル列の幅。
const double _labelWidth = 180;

/// ラベルと値の間隔。
const double _labelGap = 16;

/// ラベルの体裁。登録画面と同じ。
const TextStyle _labelStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
);

/// 値の体裁。パスワードリセット画面のユーザー名・メールアドレスと同じ 16px・黒
/// （ADR 0010・0015）。
const TextStyle _valueStyle = TextStyle(fontSize: 16);

/// マイページ（ADR 0015）。
///
/// ログインに成功したとき、`context.go('/me')` で開く。ログイン中のユーザーの
/// ユーザー名とメールアドレスを表示する。
///
/// **この画面から離れること（「戻る」・ブラウザの戻る）はログアウトを伴う。**
/// 確認とログアウトは `router.dart` の `onExit` が行う。「戻る」は `go('/')` を
/// 呼ぶだけで、ブラウザの戻るボタンと同じ経路を通る。
///
/// パスワード変更画面を URL で直接開いた・再読み込みした場合も、go_router はこの
/// 画面を下に積むため、ユーザーの取得とその失敗の扱いはこの画面が一手に担う。
class MyPageScreen extends HookConsumerWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionViewModelProvider);

    // 画面を開いたときの取得。build の最中に状態を変更できないため、最初の
    // フレームの後に始める（既存の画面と同じ考え方）。
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final failure = await ref
            .read(sessionViewModelProvider.notifier)
            .load();
        if (!context.mounted || failure == null) return;

        // 開いたときにログイン状態にない：ダイアログを出さずにログイン画面へ
        if (failure.isUnauthenticated) {
          context.go('/login');
          return;
        }

        // それ以外の失敗：ホーム画面へ戻す。セッションが残っていれば、開き直した
        // ときにマイページが表示される（ADR 0015）。
        await showAlertDialog(
          context,
          title: '取得に失敗しました',
          message:
              '${_failureMessage(failure)}\n'
              'しばらく待ってから、画面を開き直してください。',
        );
        if (context.mounted) context.go('/');
      });
      return null;
    }, const []);

    final user = state.user;

    return Scaffold(
      appBar: const BackAppBar(title: 'マイページ', trailing: UserMenuButton()),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: LayoutBuilder(
                builder: (context, constraints) => Container(
                  width: _boxWidth < constraints.maxWidth - kScreenPadding * 2
                      ? _boxWidth
                      : constraints.maxWidth - kScreenPadding * 2,
                  margin: const EdgeInsets.only(top: _boxPadding),
                  padding: const EdgeInsets.all(_boxPadding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row(label: 'ユーザー名', value: user?.name),
                      const SizedBox(height: 16),
                      _row(label: 'メールアドレス', value: user?.email),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (state.isLoading) const Positioned.fill(child: LoadingOverlay()),
        ],
      ),
    );
  }

  /// ラベルと値を 1 行に並べる（パスワードリセット画面の対象ユーザーの行と同じ形）。
  Widget _row({required String label, required String? value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(label, style: _labelStyle),
        ),
        const SizedBox(width: _labelGap),
        Expanded(
          // 取得が終わるまでは値がない。空文字にすると行の高さが 0 になり、値が
          // 入った瞬間に箱が伸びるため、幅を持たない空白文字で高さだけを確保する。
          child: Text(value ?? ' ', style: _valueStyle),
        ),
      ],
    );
  }
}

/// 取得に失敗した理由を、アラートの 1 行目の文言へ変換する。
///
/// 利用するのは一般ユーザーのため、コンテナの起動など開発者向けの案内は出さない。
String _failureMessage(AuthFailure failure) => switch (failure) {
  AuthNetworkFailure() => 'サーバーに接続できませんでした。',
  AuthApiFailure(:final message) => message,
  AuthFormatFailure() => 'サーバーの応答を解釈できませんでした。',
};
