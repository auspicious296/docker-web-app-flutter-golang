import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../domain/models/user_failure.dart';
import '../../core/app_dialogs.dart';
import '../../core/back_app_bar.dart';
import '../../core/content_width.dart';
import '../../core/field_error.dart';
import '../../core/loading_overlay.dart';
import '../view_model/user_delete_view_model.dart';
import '../view_model/users_view_model.dart';

/// フォームを囲む箱の幅。登録画面と同じ値を使う。
///
/// 以下のレイアウト定数はいずれも登録画面と揃えている。画面を行き来したときに
/// 箱とラベル列の位置が動かないようにするため。
const double _boxWidth = 720;

/// 箱の内側の余白。
const double _boxPadding = 32;

/// ラベル列の幅。登録画面の「パスワード（確認用）」に合わせた値。
///
/// この画面の最長ラベルは「メールアドレス」で 180 まで要らないが、他の画面と
/// 同じ値にしておくことで、画面を行き来したときに入力欄の左端が動かない。
const double _labelWidth = 180;

/// ラベルと入力欄の間隔。
const double _labelGap = 16;

/// エラー表示と「削除する」ボタンに使う赤。
///
/// エラー表示の背景（`FieldError`）・一覧の「削除」ボタンと同じ値。ボタンを同じ
/// 赤にしているのは、**取り返しのつかない操作であることを押す前に伝えられる
/// 要素が、この画面ではボタンの色だけ**だからである。エラーの赤とは位置も形も
/// 違う（入力欄の直下の小さな箱と枠線 / フォーム下端中央の塗りつぶしボタン）ため、
/// 両方が同時に出ても取り違える場面がない。
const Color _errorColor = Color(0xFFD32F2F);

/// 入力欄の左に置くラベルの体裁。登録画面と同じ。
const TextStyle _labelStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
);

/// 対象ユーザーの情報を出すときの体裁。パスワードリセット画面と同じ。
///
/// 入力欄の中の文字と同じ 16px・黒。編集画面の「編集前の値」（14px グレー）は
/// すぐ下の入力欄に同じ値がある参照用だが、この画面のユーザー名とメールアドレス
/// は対応する入力欄がなく、これが唯一の表示である。役目も「誰を削除するのか」を
/// 示すことで、削除確認入力より弱いわけではない。
const TextStyle _targetValueStyle = TextStyle(fontSize: 16);

/// ラベルを入力欄の中の文字と同じ高さに揃えるための上の余白。
///
/// 入力欄の内側の余白から、ラベルと入力欄の文字サイズの差を引いた値（登録画面と
/// 同じ）。対象ユーザーの行はラベルと同じ 16px のテキストなので、この余白は不要。
const double _labelTopGapForField = 15;

/// ユーザー情報削除画面。
///
/// 一覧画面から `context.push` で開く。フォームは登録画面から**ユーザー名と
/// メールアドレスの入力欄を対象ユーザーの情報を示すテキストに置き換え、入力欄を
/// 削除確認入力の 1 欄だけにした**形である。
///
/// この画面は**離脱確認を出さない**。破棄して困る入力が存在しないためで、ルート側
/// に `onExit` を置いていない。一覧への指示は `context.pop` の戻り値
/// （[UserDeleteResult]）で返す。成功・404・成否不明のいずれでも自分で `pop` を
/// 呼ぶため、値を渡せないブラウザの戻るボタンだけを通る経路が存在しない
/// （パスワードリセット画面が `onExit` へ寄せた理由は、この画面には当てはまらない）。
class UserDeleteScreen extends HookConsumerWidget {
  const UserDeleteScreen({super.key, required this.userId});

  /// 対象のユーザー ID。URL のパス（`/users/{id}/delete`）から受け取る。
  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = userDeleteViewModelProvider(userId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);

    final controller = useTextEditingController();
    final focusNode = useFocusNode();

    // 画面を開いたときの取得。build の最中に状態を変更できないため、最初の
    // フレームの後に始める（編集画面・パスワードリセット画面と同じ考え方）。
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final failure = await viewModel.load();
        if (!context.mounted || failure == null) return;

        // 404 のときだけ一覧に再読み込みを指示する。別の管理者が裏でこのユーザーを
        // 削除しており、そのユーザーの削除状態について一覧が実態と不一致を
        // 起こしている可能性があるためである。通信エラーと応答形式エラーは回線や
        // API 側の問題で、削除状態については何も語らないため指示しない。
        final isGone =
            failure is UserApiFailure && failure.code == 'not_found';

        await showAlertDialog(
          context,
          title: '取得に失敗しました',
          message: '${_failureMessage(failure)}\n'
              'OK を押すとユーザー一覧に戻り${isGone ? '、一覧を再読み込みします' : 'ます'}。',
        );
        if (context.mounted) {
          context.pop(isGone ? const UserDeleteResult.reloadNeeded() : null);
        }
      });
      return null;
    }, const []);

    return Scaffold(
      // 積んだ画面のため、ホームではなく一覧へ戻る。離脱確認は出さない。
      appBar: BackAppBar(title: 'ユーザー情報削除', onBack: () => context.pop()),
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
                        '削除確認のため'
                        '「$kDeleteConfirmationKeyword」と入力して'
                        '「削除する」ボタンを押してください。',
                      ),
                      const SizedBox(height: 24),
                      _targetRow(label: 'ユーザー名', value: state.target?.name),
                      const SizedBox(height: 16),
                      _targetRow(
                        label: 'メールアドレス',
                        value: state.target?.email,
                      ),
                      const SizedBox(height: 16),
                      _confirmationField(
                        state: state,
                        controller: controller,
                        focusNode: focusNode,
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: SizedBox(
                          width: 200,
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _errorColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _onSubmit(
                              context: context,
                              ref: ref,
                              controller: controller,
                              focusNode: focusNode,
                            ),
                            child: const Text('削除する'),
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
  /// 入力欄と同じ行構造にすることで、値の左端が下の入力欄と一直線に揃う。
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
          child: Text(value ?? ' ', style: _targetValueStyle),
        ),
      ],
    );
  }

  /// 削除確認入力の行。ラベル・入力欄・エラー表示を 1 行に並べる。
  ///
  /// 構造は登録画面の `_field` と同じだが、エラーの引き先だけが違う。この画面は
  /// 入力欄が 1 つで API 由来の検証エラーも存在しないため、項目ごとの対応表では
  /// なく状態の文字列 1 つを見る。
  Widget _confirmationField({
    required UserDeleteState state,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    final error = state.confirmationError;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          // 入力欄の中の文字と高さを揃える。エラーで行の高さが伸びたときに
          // ラベルが中央へずり下がるのを防ぐため、上端で揃えている。
          child: const Padding(
            padding: EdgeInsets.only(top: _labelTopGapForField),
            child: Text('削除確認入力', style: _labelStyle),
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
                decoration: InputDecoration(
                  hintText: kDeleteConfirmationKeyword,
                  border: _border(),
                  enabledBorder: _border(hasError: error != null),
                  focusedBorder: _border(hasError: error != null),
                ),
                // 離脱確認を出さないため、入力の有無を ViewModel へ渡す必要がない
                // （登録画面・パスワードリセット画面との違い）。
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

  /// 「削除する」を押したときの処理。
  ///
  /// 検証 → 確認ダイアログ → 削除の順に進む。検証を通らなければ確認ダイアログは
  /// 出さず、通信も起きない。
  Future<void> _onSubmit({
    required BuildContext context,
    required WidgetRef ref,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) async {
    final provider = userDeleteViewModelProvider(userId);
    final viewModel = ref.read(provider.notifier);

    // 検証を通らなかった場合、**入力値は消さない**。エラーになるのは目に見える
    // 誤りだけ（前後の空白は照合前に除かれる）なので、打った文字を残しておけば
    // 案内文の語と見比べてどこが違うかを必ず特定できる。
    if (!viewModel.validate(controller.text)) {
      focusNode.requestFocus();
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: '削除確認',
      message: 'ユーザー情報の削除を実行しますか？',
    );
    if (!confirmed || !context.mounted) return;

    // 完了ダイアログの文言は一覧の表示状態で変わるため、削除を実行する前に読んで
    // おく。読むだけで、一覧の書き換えは一覧画面が行う。
    final includeDeleted = ref.read(usersViewModelProvider).includeDeleted;

    final outcome = await viewModel.delete();
    if (!context.mounted || outcome == null) return;

    switch (outcome) {
      case UserDeleteSuccess(:final deleted):
        await showAlertDialog(
          context,
          title: '削除が完了しました',
          message: 'ユーザー情報を削除しました。\n'
              'OK を押すとユーザー一覧に戻り${includeDeleted ? 'ます' : '、一覧を再読み込みします'}。',
        );
        if (context.mounted) {
          context.pop(UserDeleteResult.deleted(deleted));
        }

      case UserDeleteGone():
        // 「失敗しました」とは言わない。対象はすでに削除されており、管理者が
        // 望んだ状態は成立しているためである。誰の操作でいつ起きたのかを示し、
        // 自分の操作を疑わせないようにする。
        await showAlertDialog(
          context,
          title: 'すでに削除されています',
          message: 'このユーザーは、別の管理者の操作などにより、'
              'この画面を開いた後にすでに削除されています。\n'
              '削除された状態になっているため、あらためて操作していただく必要は'
              'ありません。\n'
              'OK を押すとユーザー一覧に戻り、一覧を再読み込みします。',
        );
        if (context.mounted) {
          context.pop(const UserDeleteResult.reloadNeeded());
        }

      case UserDeleteUnknown():
        await showAlertDialog(
          context,
          title: '削除できたか確認できませんでした',
          message: 'サーバーに接続できず、削除できたかどうかを確認できませんでした。\n'
              'OK を押すとユーザー一覧に戻り、一覧を再読み込みします。\n'
              '削除されているかご確認ください。',
        );
        if (context.mounted) {
          context.pop(const UserDeleteResult.reloadNeeded());
        }

      case UserDeleteFailed(:final message):
        // この経路だけ画面に留まる。入力もそのまま残るため、もう一度押せる。
        await showAlertDialog(
          context,
          title: '削除に失敗しました',
          message: message,
        );
    }
  }
}

/// 取得に失敗した理由を画面の文言へ変換する。
///
/// 「サーバーに届いていない」のか「API が不具合を返した」のかを切り分けられる
/// ようにするため、一覧画面・編集画面と同じ粒度で出し分ける。
///
/// 404 だけは API の文言（「ユーザーが見つかりません。」）に 1 文を足す。削除実行時
/// の 404 と違い、こちらは一度も取得できていないため、**もともと存在しない ID
/// だった可能性**（URL を直接開いた場合など）が残る。断定はしない。
String _failureMessage(UserFailure failure) => switch (failure) {
  UserNetworkFailure() => 'サーバーに接続できませんでした。コンテナが起動しているか確認してください。',
  UserApiFailure(code: 'not_found', :final message) =>
    '$message すでに削除された可能性があります。',
  UserApiFailure(:final message) => message,
  UserFormatFailure() => 'サーバーの応答を解釈できませんでした。',
};
