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
import '../view_model/user_edit_view_model.dart';

/// フォームを囲む箱の幅。登録画面と同じ値を使う。
///
/// 2 つの画面を行き来したときに箱の位置と大きさが動かないようにするため、
/// 以下のレイアウト定数はいずれも登録画面と揃えている。
const double _boxWidth = 720;

/// 箱の内側の余白。
const double _boxPadding = 32;

/// ラベル列の幅。
///
/// この画面の最長ラベルは「メールアドレス」で 180px は余るが、登録画面と同じ値に
/// している。片方だけ詰めると、一覧 → 登録 → 一覧 → 編集と移動したときに入力欄の
/// 左端が画面ごとにずれる。
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

/// 入力欄の直上に置く「編集前の値」の体裁。
///
/// 入力欄の中の文字（16px・黒）から 1 段落とす。同じ体裁で並べると、取得直後は
/// 同じ値が 2 回続くため、どちらが編集できる値なのかが枠線だけの手がかりになる。
const TextStyle _originalValueStyle = TextStyle(
  fontSize: 14,
  color: Color(0xFF616161),
);

/// 「編集前の値」をラベルの文字とベースラインで揃えるための上の余白。
///
/// ラベルは 16px、この行は 14px で、文字の上端を合わせると下端がずれる。差の分だけ
/// 押し下げて、2 つの文字の下端を揃えている。
const double _originalValueTopGap = 2;

/// ユーザー編集画面。
///
/// 一覧画面から `context.push` で開く。基本の動作・レイアウトは登録画面と同じで、
/// 次の 3 点だけが異なる。
///
/// 1. 画面を開いた時点でユーザーを取得し、入力欄に埋め込む。取得に失敗したら
///    アラートを出して画面を閉じる
/// 2. 各入力欄の直上に、取得した時点の値をテキストで置く。入力欄を書き換えても
///    この行は変わらないため、どのユーザーを編集しているのかが最後まで分かる
/// 3. 「更新する」を押したとき、入力が元の値と同じなら通信せずアラートを出す
class UserEditScreen extends HookConsumerWidget {
  const UserEditScreen({super.key, required this.userId});

  /// 編集対象のユーザー ID。URL のパス（`/users/{id}/edit`）から受け取る。
  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = userEditViewModelProvider(userId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);

    // 確認用パスワードを含む登録画面と違い、この画面の入力欄は 2 つだけ
    final controllers = {
      UserFormField.name: useTextEditingController(),
      UserFormField.email: useTextEditingController(),
    };
    final focusNodes = {
      UserFormField.name: useFocusNode(),
      UserFormField.email: useFocusNode(),
    };

    // 画面を開いたときの取得。build の最中に状態を変更できないため、最初の
    // フレームの後に始める（一覧画面の initState と同じ考え方）。
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final failure = await viewModel.load();
        if (!context.mounted) return;

        if (failure == null) {
          final original = ref.read(provider).original!;
          controllers[UserFormField.name]!.text = original.name;
          controllers[UserFormField.email]!.text = original.email;
          return;
        }

        await showAlertDialog(
          context,
          title: '取得に失敗しました',
          message: '${_failureMessage(failure)}\n'
              'OK を押すとユーザー一覧に戻ります。',
        );
        // 値を返さずに閉じる。一覧は表示も行の選択もそのまま残る。
        if (context.mounted) context.pop();
      });
      return null;
    }, const []);

    return Scaffold(
      // 積んだ画面のため、ホームではなく一覧へ戻る。pop すると onExit が走り、
      // 元の値から変わっていれば破棄の確認が入る（ブラウザの戻ると同じ経路）。
      appBar: BackAppBar(title: 'ユーザー情報編集', onBack: () => context.pop()),
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
                        'ユーザー情報を編集後に「更新する」ボタンを押してください。',
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
                        originalValue: state.original?.name,
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
                        originalValue: state.original?.email,
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: SizedBox(
                          width: 200,
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              // 一覧画面の「編集」と同じ青。押した先の操作が
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
                            child: const Text('更新する'),
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

  /// ラベル・編集前の値・入力欄・エラー表示を 1 行に並べる。
  ///
  /// 右の列は上から「編集前の値」「入力欄」「エラー表示」の 3 段で、ラベルは
  /// その 1 段目にベースラインを揃える。エラーで行の高さが伸びてもラベルが
  /// 中央へずり下がらないようにするため、行全体は上端で揃えている。
  Widget _field({
    required UserEditState state,
    required UserEditViewModel viewModel,
    required Map<UserFormField, TextEditingController> controllers,
    required FocusNode focusNode,
    required UserFormField field,
    required String label,
    required String hint,
    required String? originalValue,
  }) {
    final error = state.errors[field];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(label, style: _labelStyle),
        ),
        const SizedBox(width: _labelGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: _originalValueTopGap),
                // 取得が終わるまでは値がない。空文字にすると行の高さが 0 になり、
                // 値が入った瞬間にフォーム全体が下へずれるため、幅を持たない
                // 空白文字で行の高さだけを確保しておく。
                child: Text(
                  originalValue ?? ' ',
                  style: _originalValueStyle,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: controllers[field],
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: hint,
                  border: _border(),
                  enabledBorder: _border(hasError: error != null),
                  focusedBorder: _border(hasError: error != null),
                ),
                // 離脱確認の判定に使う真偽値だけを ViewModel へ渡す。入力値
                // そのものは ViewModel に保持されない。
                onChanged: (_) => viewModel.syncEdited(
                  name: controllers[UserFormField.name]!.text,
                  email: controllers[UserFormField.email]!.text,
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

  /// 「更新する」を押したときの処理。
  Future<void> _onSubmit({
    required BuildContext context,
    required WidgetRef ref,
    required Map<UserFormField, TextEditingController> controllers,
    required Map<UserFormField, FocusNode> focusNodes,
  }) async {
    final provider = userEditViewModelProvider(userId);

    final outcome = await ref
        .read(provider.notifier)
        .update(
          name: controllers[UserFormField.name]!.text,
          email: controllers[UserFormField.email]!.text,
        );
    if (!context.mounted) return;

    switch (outcome) {
      case UserEditSuccess(:final updated):
        await showAlertDialog(
          context,
          title: '更新が完了しました',
          message: 'ユーザー情報を更新しました。\n'
              'OK を押すとユーザー一覧に戻ります。',
        );
        // 更新後のユーザーを返す。一覧はこの値でその 1 行だけを差し替える。
        if (context.mounted) context.pop(UserEditResult.updated(updated));

      case UserEditNotEdited():
        await showAlertDialog(
          context,
          title: '変更されていません',
          message: 'ユーザー情報が編集されていません。\n'
              '内容を変更してから「更新する」ボタンを押してください。',
        );

      case UserEditGone(:final message):
        await showAlertDialog(
          context,
          title: '更新に失敗しました',
          message: '$message\n'
              'OK を押すとユーザー一覧に戻り、一覧を再読み込みします。',
        );
        if (context.mounted) {
          context.pop(const UserEditResult.reloadNeeded());
        }

      case UserEditUnknown():
        await showAlertDialog(
          context,
          title: '更新できたか確認できませんでした',
          message: 'サーバーに接続できませんでした。\n'
              'OK を押すとユーザー一覧に戻り、一覧を再読み込みします。\n'
              '更新されているかご確認ください。',
        );
        if (context.mounted) {
          context.pop(const UserEditResult.reloadNeeded());
        }

      case UserEditFailed(:final message):
        await showAlertDialog(
          context,
          title: '更新に失敗しました',
          message: message,
        );

      case UserEditInvalid(:final alertMessage):
        _afterInvalid(ref: ref, focusNodes: focusNodes);
        if (alertMessage != null) {
          await showAlertDialog(
            context,
            title: '更新に失敗しました',
            message: alertMessage,
          );
        }
    }
  }

  /// 検証エラーが出たあとの後始末。
  ///
  /// 登録画面はパスワードに関するエラーで 2 つの欄をクリアするが、この画面には
  /// パスワードの欄がないため、残るのはフォーカスの移動だけになる。
  void _afterInvalid({
    required WidgetRef ref,
    required Map<UserFormField, FocusNode> focusNodes,
  }) {
    final errors = ref.read(userEditViewModelProvider(userId)).errors;
    if (errors.isEmpty) return;

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
/// ようにするため、一覧画面と同じ粒度で出し分ける。
String _failureMessage(UserFailure failure) => switch (failure) {
  UserNetworkFailure() => 'サーバーに接続できませんでした。コンテナが起動しているか確認してください。',
  UserApiFailure(:final message) => message,
  UserFormatFailure() => 'サーバーの応答を解釈できませんでした。',
};
