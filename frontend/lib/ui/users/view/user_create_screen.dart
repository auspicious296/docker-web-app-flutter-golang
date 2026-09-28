import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../domain/models/user_form_field.dart';
import '../../../domain/models/user_validation.dart';
import '../../core/app_dialogs.dart';
import '../../core/back_app_bar.dart';
import '../../core/content_width.dart';
import '../../core/field_error.dart';
import '../../core/loading_overlay.dart';
import '../view_model/user_create_view_model.dart';

/// フォームを囲む箱の幅。画面がこれより狭ければ画面幅に従う。
///
/// 入力欄（460px）が一般的なメールアドレスを折り返さずに表示できる幅から
/// 逆算した値。一覧画面のような全幅のレイアウトにしないのは、入力欄を
/// コンテンツ幅（最大 1,600px）まで広げても読みにくくなるだけのため。
const double _boxWidth = 720;

/// 箱の内側の余白。
const double _boxPadding = 32;

/// ラベル列の幅。最も長い「パスワード（確認用）」が折り返さずに収まる幅。
const double _labelWidth = 180;

/// ラベルと入力欄の間隔。
const double _labelGap = 16;

/// 入力欄が赤くなるときの色。エラー表示の背景と同じ。
const Color _errorColor = Color(0xFFD32F2F);

/// 入力欄の左に置くラベルの体裁。
///
/// 大きさを入力欄の中の文字（Material 3 の既定は 16px）に揃える。既定のままだと
/// 14px でラベルだけが一段小さく見えるため。太さは w600 までとし、w700 にはしない
/// （エラー表示の赤い箱より目立たせない）。
const TextStyle _labelStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
);

/// ユーザー新規登録画面。
///
/// 一覧画面から `context.push` で開く。入力の検証は「登録する」を押した時点で
/// 行い、誤りがあれば各入力欄の直下に表示する。入力途中に画面を離れようとした
/// ときの確認は、ルート側（`router.dart` の `onExit`）が持つ。
///
/// `HookConsumerWidget` にしているのは、入力中の文字列・フォーカス・パスワードの
/// 表示切り替えという **ViewModel が持つ必要のない状態**を、`initState` や
/// `dispose` を書かずに扱うため。
class UserCreateScreen extends HookConsumerWidget {
  const UserCreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userCreateViewModelProvider);
    final viewModel = ref.read(userCreateViewModelProvider.notifier);

    final controllers = {
      for (final field in UserFormField.values) field: useTextEditingController(),
    };
    final focusNodes = {
      for (final field in UserFormField.values) field: useFocusNode(),
    };
    final showPassword = useState(false);

    return Scaffold(
      // 積んだ画面のため、ホームではなく一覧へ戻る。pop すると onExit が走り、
      // 入力があれば破棄の確認が入る（ブラウザの戻るボタンと同じ経路）。
      appBar: BackAppBar(title: 'ユーザー新規登録', onBack: () => context.pop()),
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
                      // フォームの冒頭に置く案内文。この画面で何をすればよいかを
                      // 最初に示す。
                      const Text(
                        '新規ユーザーの情報を入力して「登録する」ボタンを押してください。',
                      ),
                      const SizedBox(height: 24),
                      _field(
                        state: state,
                        viewModel: viewModel,
                        controllers: controllers,
                        focusNode: focusNodes[UserFormField.name]!,
                        field: UserFormField.name,
                        label: 'ユーザー名',
                        hint: '$kMaxNameLength 文字以内で入力してください',
                      ),
                      const SizedBox(height: 16),
                      _field(
                        state: state,
                        viewModel: viewModel,
                        controllers: controllers,
                        focusNode: focusNodes[UserFormField.email]!,
                        field: UserFormField.email,
                        label: 'メールアドレス',
                        hint: 'user@example.com',
                      ),
                      const SizedBox(height: 16),
                      _field(
                        state: state,
                        viewModel: viewModel,
                        controllers: controllers,
                        focusNode: focusNodes[UserFormField.password]!,
                        field: UserFormField.password,
                        label: 'パスワード',
                        hint: '半角英数字と記号で $kMinPasswordLength 文字以上',
                        obscure: !showPassword.value,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        state: state,
                        viewModel: viewModel,
                        controllers: controllers,
                        focusNode: focusNodes[UserFormField.passwordConfirmation]!,
                        field: UserFormField.passwordConfirmation,
                        label: 'パスワード（確認用）',
                        hint: '確認のためもう一度入力してください',
                        obscure: !showPassword.value,
                      ),
                      const SizedBox(height: 8),
                      // 2 つのパスワード欄をまとめて切り替えるため、両方より下に
                      // 置く。横位置は入力欄の列に合わせる（ラベル列ではない）。
                      Row(
                        children: [
                          const SizedBox(width: _labelWidth + _labelGap),
                          Expanded(
                            child: _showPasswordCheckbox(showPassword),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: SizedBox(
                          width: 200,
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              // 一覧画面の「新規登録」と同じ青。押した先の操作が
                              // 続いていることを色で示す。
                              backgroundColor: const Color(0xFF0277BD),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _onSubmit(
                              context: context,
                              ref: ref,
                              controllers: controllers,
                              focusNodes: focusNodes,
                            ),
                            child: const Text('登録する'),
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

  /// ラベル・入力欄・エラー表示を 1 行に並べる。
  ///
  /// ラベルは入力欄の上端に揃える。エラーで行の高さが伸びたときに、ラベルが
  /// 中央へずり下がるのを防ぐため。エラー表示は入力欄の列にだけ置き、ラベル列の
  /// 下には回り込ませない。
  Widget _field({
    required UserCreateState state,
    required UserCreateViewModel viewModel,
    required Map<UserFormField, TextEditingController> controllers,
    required FocusNode focusNode,
    required UserFormField field,
    required String label,
    required String hint,
    bool obscure = false,
  }) {
    final error = state.errors[field];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          // 入力欄の中の文字と高さを揃える。上の余白は、入力欄の内側の余白から
          // 文字サイズの差を引いた値。
          child: Padding(
            padding: const EdgeInsets.only(top: 15),
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
                // そのものは渡さない（1 文字ごとに状態を作り直さないため）。
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
  ///
  /// どの欄が問題なのかを、下のエラー表示と見比べずに判断できるようにするため。
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

  /// 「登録する」を押したときの処理。
  Future<void> _onSubmit({
    required BuildContext context,
    required WidgetRef ref,
    required Map<UserFormField, TextEditingController> controllers,
    required Map<UserFormField, FocusNode> focusNodes,
  }) async {
    final viewModel = ref.read(userCreateViewModelProvider.notifier);

    final outcome = await viewModel.register(
      name: controllers[UserFormField.name]!.text,
      email: controllers[UserFormField.email]!.text,
      password: controllers[UserFormField.password]!.text,
      passwordConfirmation:
          controllers[UserFormField.passwordConfirmation]!.text,
    );
    if (!context.mounted) return;

    switch (outcome) {
      case UserCreateSuccess():
        await showAlertDialog(
          context,
          title: '登録が完了しました',
          message: 'ユーザーを登録しました。\n'
              'OK を押すとユーザー一覧に戻り、一覧を再読み込みします。',
        );
        if (context.mounted) context.pop(true);

      case UserCreateUnknown():
        await showAlertDialog(
          context,
          title: '登録できたか確認できませんでした',
          message: 'サーバーに接続できませんでした。\n'
              'OK を押すとユーザー一覧に戻り、一覧を再読み込みします。\n'
              '登録されているかご確認ください。',
        );
        if (context.mounted) context.pop(true);

      case UserCreateFailed(:final message):
        await showAlertDialog(
          context,
          title: '登録に失敗しました',
          message: message,
        );

      case UserCreateInvalid(:final alertMessage):
        _afterInvalid(
          ref: ref,
          controllers: controllers,
          focusNodes: focusNodes,
        );
        if (alertMessage != null) {
          await showAlertDialog(
            context,
            title: '登録に失敗しました',
            message: alertMessage,
          );
        }
    }
  }

  /// 検証エラーが出たあとの後始末。
  ///
  /// パスワードに関するエラーが出たときだけ、パスワードの 2 欄をクリアする。
  /// 検証を通らなかった値を伏せ字の裏に残さないためで、ユーザー名と
  /// メールアドレスは画面に見えているためクリアしない。「パスワードを表示する」
  /// のチェックも外さない（打ち直すときこそ確認したい場面のため）。
  void _afterInvalid({
    required WidgetRef ref,
    required Map<UserFormField, TextEditingController> controllers,
    required Map<UserFormField, FocusNode> focusNodes,
  }) {
    final errors = ref.read(userCreateViewModelProvider).errors;
    if (errors.isEmpty) return;

    if (errors.containsKey(UserFormField.password) ||
        errors.containsKey(UserFormField.passwordConfirmation)) {
      controllers[UserFormField.password]!.clear();
      controllers[UserFormField.passwordConfirmation]!.clear();
      ref.read(userCreateViewModelProvider.notifier).setHasInput(
            hasInput: controllers.values.any((c) => c.text.isNotEmpty),
          );
    }

    // 宣言の順序＝画面に並ぶ順序。上から見て最初にエラーのある欄へ移す。
    for (final field in UserFormField.values) {
      if (errors.containsKey(field)) {
        focusNodes[field]!.requestFocus();
        return;
      }
    }
  }
}
