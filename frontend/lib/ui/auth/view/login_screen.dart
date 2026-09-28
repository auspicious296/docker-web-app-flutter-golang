import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../domain/models/auth_form_field.dart';
import '../../core/app_dialogs.dart';
import '../../core/back_app_bar.dart';
import '../../core/content_width.dart';
import '../../core/field_error.dart';
import '../../core/loading_overlay.dart';
import '../view_model/login_view_model.dart';

/// フォームを囲む箱の幅。登録画面・パスワードリセット画面と同じ値を使う。
///
/// 以下のレイアウト定数はいずれも既存の画面と揃えている。画面を行き来したときに
/// 箱とラベル列の位置が動かないようにするため。
const double _boxWidth = 720;

/// 箱の内側の余白。
const double _boxPadding = 32;

/// ラベル列の幅。
const double _labelWidth = 180;

/// ラベルと入力欄の間隔。
const double _labelGap = 16;

/// 入力欄が赤くなるときの色。エラー表示の背景と同じ。
const Color _errorColor = Color(0xFFD32F2F);

/// 入力欄の左に置くラベルの体裁。登録画面と同じ。
const TextStyle _labelStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
);

/// ラベルを入力欄の中の文字と同じ高さに揃えるための上の余白（登録画面と同じ）。
const double _labelTopGapForField = 15;

/// ログイン画面（ADR 0015）。
///
/// ホーム画面の「ユーザーログイン」とメニューの「ログアウト」の後に
/// `context.go('/login')` で開く。ログイン状態のまま開いた場合は、`router.dart`
/// の `redirect` がマイページへ移す。
///
/// 「戻る」はホーム画面へ戻る。入力欄は 2 つだけで、失っても打ち直す手間が小さい
/// ため、離脱確認は出さない。
///
/// ログアウトした後やログイン状態が切れた後に移ってきた場合は、ログインしていた
/// ユーザーのメールアドレスを [initialEmail] で受け取り、入力欄に入れておく。
class LoginScreen extends HookConsumerWidget {
  const LoginScreen({super.key, this.initialEmail});

  /// メールアドレスの入力欄に最初から入れておく値。なければ空欄。
  final String? initialEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loginViewModelProvider);

    final controllers = {
      LoginField.email: useTextEditingController(text: initialEmail),
      LoginField.password: useTextEditingController(),
    };
    final focusNodes = {
      LoginField.email: useFocusNode(),
      LoginField.password: useFocusNode(),
    };

    return Scaffold(
      appBar: const BackAppBar(title: 'ユーザーログイン'),
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
                      const Text(
                        'メールアドレスとパスワードを入力して'
                        '「ログイン」ボタンを押してください。',
                      ),
                      const SizedBox(height: 24),
                      _field(
                        state: state,
                        controller: controllers[LoginField.email]!,
                        focusNode: focusNodes[LoginField.email]!,
                        field: LoginField.email,
                        label: 'メールアドレス',
                      ),
                      const SizedBox(height: 16),
                      _field(
                        state: state,
                        controller: controllers[LoginField.password]!,
                        focusNode: focusNodes[LoginField.password]!,
                        field: LoginField.password,
                        label: 'パスワード',
                        obscure: true,
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: SizedBox(
                          width: 200,
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0277BD),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _onSubmit(
                              context: context,
                              ref: ref,
                              controllers: controllers,
                              focusNodes: focusNodes,
                            ),
                            child: const Text('ログイン'),
                          ),
                        ),
                      ),
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

  /// ラベル・入力欄・エラー表示を 1 行に並べる（登録画面と同じ構造）。
  Widget _field({
    required LoginState state,
    required TextEditingController controller,
    required FocusNode focusNode,
    required LoginField field,
    required String label,
    bool obscure = false,
  }) {
    final error = state.errors[field];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: _labelTopGapForField),
            child: Text(label, style: _labelStyle),
          ),
        ),
        const SizedBox(width: _labelGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                focusNode: focusNode,
                obscureText: obscure,
                decoration: InputDecoration(
                  border: _border(),
                  enabledBorder: _border(hasError: error != null),
                  focusedBorder: _border(hasError: error != null),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 4),
                FieldError(message: error),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 入力欄の枠線。エラーが出ている欄は枠線も赤くする。
  OutlineInputBorder _border({bool hasError = false}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: hasError
        ? const BorderSide(color: _errorColor)
        : const BorderSide(),
  );

  /// 「ログイン」を押したときの処理。
  Future<void> _onSubmit({
    required BuildContext context,
    required WidgetRef ref,
    required Map<LoginField, TextEditingController> controllers,
    required Map<LoginField, FocusNode> focusNodes,
  }) async {
    final outcome = await ref
        .read(loginViewModelProvider.notifier)
        .login(
          email: controllers[LoginField.email]!.text,
          password: controllers[LoginField.password]!.text,
        );
    if (!context.mounted) return;

    switch (outcome) {
      case LoginSuccess():
        context.go('/me');

      case LoginInvalid(:final alertMessage):
        // 宣言の順序＝画面に並ぶ順序。上から見て最初にエラーのある欄へ移す。
        final errors = ref.read(loginViewModelProvider).errors;
        for (final field in LoginField.values) {
          if (errors.containsKey(field)) {
            focusNodes[field]?.requestFocus();
            break;
          }
        }
        if (alertMessage != null) {
          await showAlertDialog(
            context,
            title: 'ログインできませんでした',
            message: alertMessage,
          );
        }

      case LoginFailed(:final message, :final clearPassword):
        // 401（メールアドレスまたはパスワードの誤り）のときだけ、誤っていた可能性
        // のある値を伏せ字の裏に残さないよう、パスワード欄をクリアする。
        // メールアドレスは打ち直さずに済むよう残す（ADR 0015）。
        if (clearPassword) controllers[LoginField.password]!.clear();
        await showAlertDialog(context, title: 'ログインできませんでした', message: message);
        if (clearPassword && context.mounted) {
          focusNodes[LoginField.password]!.requestFocus();
        }
    }
  }
}
