import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../domain/models/auth_form_field.dart';
import '../../../domain/models/user_validation.dart';
import '../../core/app_dialogs.dart';
import '../../core/back_app_bar.dart';
import '../../core/content_width.dart';
import '../../core/field_error.dart';
import '../../core/loading_overlay.dart';
import '../view_model/password_change_view_model.dart';
import '../view_model/session_view_model.dart';
import 'logout_flow.dart';
import 'user_menu_button.dart';

/// フォームを囲む箱の幅。登録画面・パスワードリセット画面と同じ値を使う。
///
/// 以下のレイアウト定数はいずれも既存の画面と揃えている。画面を行き来したときに
/// 箱とラベル列の位置が動かないようにするため。
const double _boxWidth = 720;

/// 箱の内側の余白。
const double _boxPadding = 32;

/// ラベル列の幅。最も長い「新しいパスワード（確認用）」はこの幅に収まらないため、
/// 「（確認用）」の前で改行して 2 行で表示する。
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

/// パスワード変更画面（ADR 0015）。
///
/// マイページのメニューの「パスワード変更」から `context.push` で開く。URL は
/// マイページと同じ `/me` のまま変わらない（ユーザー一覧から開く画面と同じ形）。
///
/// フォームはパスワードリセット画面をベースに、「現在のパスワード」の欄を足した
/// 形である。ユーザー名とメールアドレスは表示しない。タイトルバーの「ユーザー名」
/// ボタンで分かり、ログインしている本人が操作しているためである。
///
/// 入力があるときに離れようとすると、`router.dart` の `onExit` が破棄の確認を出す。
class PasswordChangeScreen extends HookConsumerWidget {
  const PasswordChangeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(passwordChangeViewModelProvider);
    final viewModel = ref.read(passwordChangeViewModelProvider.notifier);
    // メニューからのログアウトの処理中も、この画面をローダーで覆う
    final isSessionLoading = ref.watch(
      sessionViewModelProvider.select((s) => s.isLoading),
    );

    final controllers = {
      PasswordChangeField.currentPassword: useTextEditingController(),
      PasswordChangeField.newPassword: useTextEditingController(),
      PasswordChangeField.newPasswordConfirmation: useTextEditingController(),
    };
    final focusNodes = {
      PasswordChangeField.currentPassword: useFocusNode(),
      PasswordChangeField.newPassword: useFocusNode(),
      PasswordChangeField.newPasswordConfirmation: useFocusNode(),
    };
    final showPassword = useState(false);

    Widget field(PasswordChangeField field, String label, String? hint) =>
        _field(
          state: state,
          viewModel: viewModel,
          controllers: controllers,
          focusNode: focusNodes[field]!,
          field: field,
          label: label,
          hint: hint,
          obscure: !showPassword.value,
        );

    return Scaffold(
      // 積んだ画面のため、マイページへ戻る。pop すると onExit が走り、入力があれば
      // 破棄の確認が入る（ブラウザの戻るボタンと同じ経路）。
      appBar: BackAppBar(
        title: 'パスワード変更',
        onBack: () => context.pop(),
        trailing: const UserMenuButton(showPasswordChange: false),
      ),
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
                        '現在のパスワードと新しいパスワードを入力して'
                        '「変更する」ボタンを押してください。',
                      ),
                      const SizedBox(height: 24),
                      field(
                        PasswordChangeField.currentPassword,
                        '現在のパスワード',
                        null,
                      ),
                      const SizedBox(height: 16),
                      field(
                        PasswordChangeField.newPassword,
                        '新しいパスワード',
                        '半角英数字と記号で $kMinPasswordLength 文字以上',
                      ),
                      const SizedBox(height: 16),
                      field(
                        PasswordChangeField.newPasswordConfirmation,
                        '新しいパスワード\n（確認用）',
                        '確認のためもう一度入力してください',
                      ),
                      const SizedBox(height: 8),
                      // 3 つのパスワード欄をまとめて切り替えるため、すべてより下に
                      // 置く。横位置は入力欄の列に合わせる（ラベル列ではない）。
                      Row(
                        children: [
                          const SizedBox(width: _labelWidth + _labelGap),
                          Expanded(child: _showPasswordCheckbox(showPassword)),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: SizedBox(
                          width: 200,
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              // パスワードリセット画面の「実行する」と同じ青
                              backgroundColor: const Color(0xFF0277BD),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _onSubmit(
                              context: context,
                              ref: ref,
                              controllers: controllers,
                              focusNodes: focusNodes,
                            ),
                            child: const Text('変更する'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (state.isLoading || isSessionLoading)
            const Positioned.fill(child: LoadingOverlay()),
        ],
      ),
    );
  }

  /// ラベル・入力欄・エラー表示を 1 行に並べる（登録画面と同じ構造）。
  Widget _field({
    required PasswordChangeState state,
    required PasswordChangeViewModel viewModel,
    required Map<PasswordChangeField, TextEditingController> controllers,
    required FocusNode focusNode,
    required PasswordChangeField field,
    required String label,
    required String? hint,
    required bool obscure,
  }) {
    final error = state.errors[field];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          // 入力欄の中の文字と高さを揃える。エラーで行の高さが伸びたときに
          // ラベルが中央へずり下がるのを防ぐため、上端で揃えている。
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
                controller: controllers[field],
                focusNode: focusNode,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: hint,
                  border: _border(),
                  enabledBorder: _border(hasError: error != null),
                  focusedBorder: _border(hasError: error != null),
                ),
                // 離脱確認の判定に使う真偽値だけを ViewModel へ渡す。入力値
                // そのものは渡さない。
                onChanged: (_) => viewModel.setHasInput(
                  hasInput: controllers.values.any((c) => c.text.isNotEmpty),
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

  Widget _showPasswordCheckbox(ValueNotifier<bool> showPassword) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: showPassword.value,
          onChanged: (value) => showPassword.value = value ?? false,
        ),
        // ラベルをタップしても切り替わるようにする
        GestureDetector(
          onTap: () => showPassword.value = !showPassword.value,
          child: const Text('パスワードを表示する'),
        ),
      ],
    );
  }

  /// 「変更する」を押したときの処理。
  Future<void> _onSubmit({
    required BuildContext context,
    required WidgetRef ref,
    required Map<PasswordChangeField, TextEditingController> controllers,
    required Map<PasswordChangeField, FocusNode> focusNodes,
  }) async {
    final outcome = await ref
        .read(passwordChangeViewModelProvider.notifier)
        .change(
          currentPassword:
              controllers[PasswordChangeField.currentPassword]!.text,
          newPassword: controllers[PasswordChangeField.newPassword]!.text,
          newPasswordConfirmation:
              controllers[PasswordChangeField.newPasswordConfirmation]!.text,
        );
    if (!context.mounted) return;

    switch (outcome) {
      case PasswordChangeSuccess():
        await showAlertDialog(
          context,
          title: 'パスワードを変更しました',
          message:
              '次回のログインから新しいパスワードを使用してください。\n'
              'ほかの端末やブラウザでログインしていた場合は、\n'
              'ログアウトされました。',
        );
        // 変更済みのため、onExit は確認を出さない（isCompleted）
        if (context.mounted) context.pop();

      case PasswordChangeInvalid(:final alertMessage):
        _afterInvalid(
          ref: ref,
          controllers: controllers,
          focusNodes: focusNodes,
        );
        if (alertMessage != null) {
          await showAlertDialog(
            context,
            title: 'パスワードを変更できませんでした',
            message: alertMessage,
          );
        }

      case PasswordChangeLocked(:final message):
        await showAlertDialog(
          context,
          title: 'パスワードを変更できませんでした',
          message: message,
        );
        if (!context.mounted) return;
        // ログイン画面へ移す。セッションが残っていれば（別の端末のログインの失敗で
        // すでにロックされていた場合）、ログイン画面からマイページへ戻される。
        _goToLogin(context, ref);

      case PasswordChangeUnauthenticated():
        await showSessionExpiredDialog(context);
        if (!context.mounted) return;
        _goToLogin(context, ref);

      case PasswordChangeUnknown():
        // 画面に留まり、入力を残す。押し直した結果で成否を判別させる（ADR 0015）。
        await showAlertDialog(
          context,
          title: 'パスワードを変更できたか確認できませんでした',
          message:
              'サーバーに接続できませんでした。\n'
              'もう一度「変更する」を押してください。\n'
              '「現在のパスワードが正しくありません」と表示された場合は、'
              'すでに新しいパスワードに変更されています。',
        );

      case PasswordChangeFailed(:final message):
        await showAlertDialog(
          context,
          title: 'パスワードを変更できませんでした',
          message: message,
        );
    }
  }

  /// ログイン状態でなくなったことを記録し、ログイン画面へ移す。
  ///
  /// ログインしていたユーザーのメールアドレスを、ログイン画面の入力欄に入れておく。
  /// ユーザーの情報は signedOut で消えるため、その前に読み取る。
  void _goToLogin(BuildContext context, WidgetRef ref) {
    final email = ref.read(sessionViewModelProvider).user?.email;
    ref.read(sessionViewModelProvider.notifier).signedOut();
    context.go('/login', extra: email);
  }

  /// 検証エラーが出たあとの後始末。
  ///
  /// **エラーが出た欄の組だけをクリアする**（ADR 0015）。組は「現在のパスワード」と
  /// 「新しいパスワード・確認用」の 2 つ。検証を通らなかった値を伏せ字の裏に残さない
  /// という既存の規則（ADR 0010）は、組の単位で成り立つ。新しいパスワードの 2 欄を
  /// 組で扱うのは、確認用だけが一致しない場合に、打ち間違えたのがどちらの欄かを
  /// 画面から判別できないためである。
  ///
  /// 「パスワードを表示する」のチェックは外さない（打ち直すときこそ確認したい）。
  void _afterInvalid({
    required WidgetRef ref,
    required Map<PasswordChangeField, TextEditingController> controllers,
    required Map<PasswordChangeField, FocusNode> focusNodes,
  }) {
    final errors = ref.read(passwordChangeViewModelProvider).errors;
    if (errors.isEmpty) return;

    final clearCurrent = errors.containsKey(
      PasswordChangeField.currentPassword,
    );
    final clearNewPair = errors.keys.any((f) => f.isNewPasswordPair);

    for (final entry in controllers.entries) {
      final isNewPair = entry.key.isNewPasswordPair;
      if ((isNewPair && clearNewPair) || (!isNewPair && clearCurrent)) {
        entry.value.clear();
      }
    }
    ref
        .read(passwordChangeViewModelProvider.notifier)
        .setHasInput(
          hasInput: controllers.values.any((c) => c.text.isNotEmpty),
        );

    // 宣言の順序＝画面に並ぶ順序。上から見て最初にエラーのある欄へ移す。
    for (final field in PasswordChangeField.values) {
      if (errors.containsKey(field)) {
        focusNodes[field]?.requestFocus();
        return;
      }
    }
  }
}
