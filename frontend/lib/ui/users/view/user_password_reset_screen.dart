import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../domain/models/user_failure.dart';
import '../../../domain/models/user_form_field.dart';
import '../../../domain/models/user_validation.dart';
import '../../core/app_dialogs.dart';
import '../../core/back_app_bar.dart';
import '../../core/content_width.dart';
import '../../core/field_error.dart';
import '../../core/loading_overlay.dart';
import '../view_model/user_password_reset_view_model.dart';

/// フォームを囲む箱の幅。登録画面と同じ値を使う。
///
/// 以下のレイアウト定数はいずれも登録画面と揃えている。画面を行き来したときに
/// 箱とラベル列の位置が動かないようにするため。
const double _boxWidth = 720;

/// 箱の内側の余白。
const double _boxPadding = 32;

/// ラベル列の幅。最も長い「パスワード（確認用）」が折り返さずに収まる幅。
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

/// 対象ユーザーの情報を出すときの体裁。
///
/// 入力欄の中の文字と同じ 16px・黒。編集画面の「編集前の値」は 14px のグレーだが、
/// あちらはすぐ下の入力欄に同じ値がある**参照用**だった。この画面のユーザー名と
/// メールアドレスは対応する入力欄がなく、これが唯一の表示である。役目も「誰の
/// パスワードを書き換えるのか」を示すことで、パスワード欄より弱いわけではない。
const TextStyle _targetValueStyle = TextStyle(fontSize: 16);

/// ラベルを入力欄の中の文字と同じ高さに揃えるための上の余白。
///
/// 入力欄の内側の余白から、ラベルと入力欄の文字サイズの差を引いた値（登録画面と
/// 同じ）。対象ユーザーの行はラベルと同じ 16px のテキストなので、この余白は不要。
const double _labelTopGapForField = 15;

/// パスワードリセット画面。
///
/// 一覧画面から `context.push` で開く。フォームは登録画面から**ユーザー名と
/// メールアドレスの入力欄を、対象ユーザーの情報を示すテキストに置き換えた**形で、
/// パスワードと確認用の 2 欄だけが入力欄である。
///
/// この画面は、閉じるときに**値を返さない**（常に `context.pop()`）。一覧へ何を
/// させるか（1 行差し替え・取り直し・何もしない）は `router.dart` の `onExit` が
/// ViewModel の状態を読んで決める。`context.pop` の戻り値ではブラウザの戻るボタン
/// を通る経路を拾えず、成否不明のあとに一覧の更新日時が古いまま残るためである。
class UserPasswordResetScreen extends HookConsumerWidget {
  const UserPasswordResetScreen({super.key, required this.userId});

  /// 対象のユーザー ID。URL のパス（`/users/{id}/password`）から受け取る。
  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = userPasswordResetViewModelProvider(userId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);

    final controllers = {
      UserFormField.password: useTextEditingController(),
      UserFormField.passwordConfirmation: useTextEditingController(),
    };
    final focusNodes = {
      UserFormField.password: useFocusNode(),
      UserFormField.passwordConfirmation: useFocusNode(),
    };
    final showPassword = useState(false);

    // 画面を開いたときの取得。build の最中に状態を変更できないため、最初の
    // フレームの後に始める（編集画面・一覧画面と同じ考え方）。
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final failure = await viewModel.load();
        if (!context.mounted || failure == null) return;

        await showAlertDialog(
          context,
          title: '取得に失敗しました',
          message: '${_failureMessage(failure)}\n'
              'OK を押すとユーザー一覧に戻ります。',
        );
        // 一覧は何も変わっていないため、onExit は一覧に何もしない
        if (context.mounted) context.pop();
      });
      return null;
    }, const []);

    return Scaffold(
      // 積んだ画面のため、ホームではなく一覧へ戻る。pop すると onExit が走り、
      // 入力があれば破棄の確認が入る（ブラウザの戻るボタンと同じ経路）。
      appBar: BackAppBar(title: 'パスワードリセット', onBack: () => context.pop()),
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
                        'パスワードと確認用に新しいパスワードを入力して'
                        '「実行する」ボタンを押してください。',
                      ),
                      const SizedBox(height: 24),
                      _targetRow(
                        label: 'ユーザー名',
                        value: state.target?.name,
                      ),
                      const SizedBox(height: 16),
                      _targetRow(
                        label: 'メールアドレス',
                        value: state.target?.email,
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
                        focusNode:
                            focusNodes[UserFormField.passwordConfirmation]!,
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
                              // 一覧画面の「パスワードリセット」と同じ青。押した先
                              // の操作が続いていることを色で示す。
                              backgroundColor: const Color(0xFF0277BD),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _onSubmit(
                              context: context,
                              ref: ref,
                              controllers: controllers,
                              focusNodes: focusNodes,
                            ),
                            child: const Text('実行する'),
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

  /// 対象ユーザーの情報を 1 行で示す。ラベル列と値の 2 段構え。
  ///
  /// 入力欄と同じ行構造にすることで、値の左端が下のパスワード欄と一直線に揃う。
  /// ラベルと値はどちらも 16px なので、上端をそのまま合わせればよい。
  Widget _targetRow({required String label, required String? value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _labelWidth, child: Text(label, style: _labelStyle)),
        const SizedBox(width: _labelGap),
        Expanded(
          // 取得が終わるまでは値がない。空文字にすると行の高さが 0 になり、値が
          // 入った瞬間にフォーム全体が下へずれるため、幅を持たない空白文字で
          // 行の高さだけを確保しておく。
          child: Text(value ?? ' ', style: _targetValueStyle),
        ),
      ],
    );
  }

  /// ラベル・入力欄・エラー表示を 1 行に並べる（登録画面と同じ構造）。
  Widget _field({
    required UserPasswordResetState state,
    required UserPasswordResetViewModel viewModel,
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

  /// 「実行する」を押したときの処理。
  Future<void> _onSubmit({
    required BuildContext context,
    required WidgetRef ref,
    required Map<UserFormField, TextEditingController> controllers,
    required Map<UserFormField, FocusNode> focusNodes,
  }) async {
    final provider = userPasswordResetViewModelProvider(userId);

    final outcome = await ref
        .read(provider.notifier)
        .reset(
          password: controllers[UserFormField.password]!.text,
          passwordConfirmation:
              controllers[UserFormField.passwordConfirmation]!.text,
        );
    if (!context.mounted) return;

    switch (outcome) {
      case UserPasswordResetSuccess(:final updated):
        // ロックはこの操作では解除されない。管理者が新しいパスワードを伝えても
        // そのユーザーはログインできないため、その 1 文だけ赤で強調する。
        await showRichAlertDialog(
          context,
          title: 'リセットが完了しました',
          message: [
            const TextSpan(text: 'パスワードをリセットしました。\n'),
            if (updated.isLocked)
              const TextSpan(
                text: 'このユーザーはアカウントがロックされたままです。\n',
                style: TextStyle(color: _errorColor),
              ),
            const TextSpan(text: 'OK を押すとユーザー一覧に戻ります。'),
          ],
        );
        // 値は返さない。一覧への差し替えは onExit が state を見て行う。
        if (context.mounted) context.pop();

      case UserPasswordResetGone(:final message):
        await showAlertDialog(
          context,
          title: 'リセットに失敗しました',
          message: '$message\n'
              'OK を押すとユーザー一覧に戻り、一覧を再読み込みします。',
        );
        if (context.mounted) context.pop();

      case UserPasswordResetUnknown():
        // 画面には留まる。パスワードの上書きは何度実行しても結果が同じなので、
        // もう一度押すことが最も確実な確認手段になる。回数の制限は設けない。
        await showAlertDialog(
          context,
          title: 'リセットできたか確認できませんでした',
          message: 'サーバーに接続できませんでした。\n'
              'もう一度お試しください。',
        );

      case UserPasswordResetFailed(:final message):
        await showAlertDialog(
          context,
          title: 'リセットに失敗しました',
          message: message,
        );

      case UserPasswordResetInvalid(:final alertMessage):
        _afterInvalid(
          ref: ref,
          controllers: controllers,
          focusNodes: focusNodes,
        );
        if (alertMessage != null) {
          await showAlertDialog(
            context,
            title: 'リセットに失敗しました',
            message: alertMessage,
          );
        }
    }
  }

  /// 検証エラーが出たあとの後始末。
  ///
  /// パスワードの 2 欄をクリアする。登録画面と同じ規則で、検証を通らなかった値を
  /// 伏せ字の裏に残さないためである。確認用だけが一致しなかった場合もパスワード欄
  /// を残さないのは、**打ち間違えたのがどちらの欄かを画面から判別できない**ため。
  /// パスワード欄を正しいものとして扱うと、確認用の欄が果たすべき役目（打ち間違い
  /// を捕まえること）が働かず、意図しないパスワードが確定し得る。
  ///
  /// この画面の入力欄はパスワードの 2 欄だけなので、結果としてフォームは空になる。
  /// 「パスワードを表示する」のチェックは外さない（打ち直すときこそ確認したい）。
  void _afterInvalid({
    required WidgetRef ref,
    required Map<UserFormField, TextEditingController> controllers,
    required Map<UserFormField, FocusNode> focusNodes,
  }) {
    final provider = userPasswordResetViewModelProvider(userId);
    final errors = ref.read(provider).errors;
    if (errors.isEmpty) return;

    for (final controller in controllers.values) {
      controller.clear();
    }
    ref.read(provider.notifier).setHasInput(hasInput: false);

    // 宣言の順序＝画面に並ぶ順序。上から見て最初にエラーのある欄へ移す。
    for (final field in UserFormField.values) {
      if (errors.containsKey(field)) {
        focusNodes[field]?.requestFocus();
        return;
      }
    }
  }
}

/// 取得に失敗した理由を画面の文言へ変換する。
///
/// 「サーバーに届いていない」のか「API が不具合を返した」のかを切り分けられる
/// ようにするため、一覧画面・編集画面と同じ粒度で出し分ける。
String _failureMessage(UserFailure failure) => switch (failure) {
  UserNetworkFailure() => 'サーバーに接続できませんでした。コンテナが起動しているか確認してください。',
  UserApiFailure(:final message) => message,
  UserFormatFailure() => 'サーバーの応答を解釈できませんでした。',
};
