import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../domain/models/auth_failure.dart';
import '../../../domain/models/auth_form_field.dart';
import '../../../domain/models/auth_validation.dart';

part 'password_change_view_model.freezed.dart';
part 'password_change_view_model.g.dart';

/// パスワード変更画面の状態。
///
/// 入力中のパスワードはここに持たない（登録画面と同じく View が hooks で保持する）。
@freezed
class PasswordChangeState with _$PasswordChangeState {
  const PasswordChangeState({
    this.isLoading = false,
    this.errors = const {},
    this.hasInput = false,
    this.isCompleted = false,
  });

  /// API の応答を待っているか。`true` のあいだ画面全体をローダーが覆う。
  final bool isLoading;

  /// 入力項目ごとの検証エラー。エラーのある項目だけが入る。
  final Map<PasswordChangeField, String> errors;

  /// 3 つの入力欄のいずれかに文字があるか。離脱確認（ルートの `onExit`）に使う。
  final bool hasInput;

  /// 変更に成功し、離脱確認を出さずに画面を離れてよい状態か。
  ///
  /// **成否不明のときは `true` にしない。** 画面に留まって押し直せるようにする
  /// ためで、そこから「戻る」を押した場合は入力を守るために確認を出す。
  final bool isCompleted;
}

/// パスワード変更の結果。View はこれを見て、出すダイアログと次の操作を決める。
@freezed
sealed class PasswordChangeOutcome with _$PasswordChangeOutcome {
  /// 変更できた。完了のダイアログを出し、OK でマイページへ戻る。
  const factory PasswordChangeOutcome.success() = PasswordChangeSuccess;

  /// 入力に誤りがある。エラーは [PasswordChangeState.errors] に入っている。
  ///
  /// [alertMessage] は、API が返した検証エラーのうち画面の入力項目へ変換
  /// できなかったものがあった場合にだけ入る（ADR 0008）。
  const factory PasswordChangeOutcome.invalid({String? alertMessage}) =
      PasswordChangeInvalid;

  /// アカウントがロックされている（403 `account_locked`）。アラートの後、ログイン
  /// 画面へ移る。今回の失敗でロックされた場合はセッションが削除されているため
  /// ログイン画面が、すでにロックされていた場合はセッションが残っているため
  /// マイページが表示される（ADR 0015）。
  const factory PasswordChangeOutcome.locked(String message) =
      PasswordChangeLocked;

  /// ログイン状態が切れていた（401）。
  const factory PasswordChangeOutcome.unauthenticated() =
      PasswordChangeUnauthenticated;

  /// 変更できたかどうか分からない。アラートを出し、画面に留まる（入力は残す）。
  ///
  /// 本人によるパスワード変更は冪等ではない。実際には変更できていた場合、押し直すと
  /// 古いパスワードを現在のパスワードとして送ることになり、「現在のパスワードが
  /// 正しくありません」が返る。この意味をダイアログで先に伝える（ADR 0015）。
  const factory PasswordChangeOutcome.unknown() = PasswordChangeUnknown;

  /// 変更できなかった。アラートを出し、画面に留まる（入力は残す）。
  const factory PasswordChangeOutcome.failed(String message) =
      PasswordChangeFailed;
}

/// パスワード変更画面の ViewModel。
///
/// autoDispose のため、画面を離れると状態は破棄される。
@riverpod
class PasswordChangeViewModel extends _$PasswordChangeViewModel {
  /// 依存する Repository。
  ///
  /// メソッドの中で `ref.read` せず、`build` で `ref.watch` して保持する
  /// （理由は `HealthViewModel` のコメントを参照）。
  late final AuthRepository _repository;

  @override
  PasswordChangeState build() {
    _repository = ref.watch(authRepositoryProvider);
    return const PasswordChangeState();
  }

  /// 入力の有無を更新する。View が各入力欄の `onChanged` から呼ぶ。
  void setHasInput({required bool hasInput}) {
    if (state.hasInput == hasInput) return;
    state = state.copyWith(hasInput: hasInput);
  }

  /// 入力を検証し、通ればパスワードを変更する。
  Future<PasswordChangeOutcome> change({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirmation,
  }) async {
    // 二重送信を防ぐ同期的なガード（登録画面と同じ理由）
    if (state.isLoading) return const PasswordChangeOutcome.invalid();

    final errors = validatePasswordChangeForm(
      currentPassword: currentPassword,
      newPassword: newPassword,
      newPasswordConfirmation: newPasswordConfirmation,
    );
    if (errors.isNotEmpty) {
      state = state.copyWith(errors: errors);
      return const PasswordChangeOutcome.invalid();
    }

    state = state.copyWith(errors: const {}, isLoading: true);
    try {
      await _repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      state = state.copyWith(isLoading: false, isCompleted: true);
      return const PasswordChangeOutcome.success();
    } on AuthFailure catch (failure) {
      state = state.copyWith(isLoading: false);
      return _outcomeOf(failure);
    }
  }

  /// 失敗の内訳を、画面が取るべき振る舞いへ変換する（ADR 0015）。
  PasswordChangeOutcome _outcomeOf(AuthFailure failure) {
    switch (failure) {
      case AuthNetworkFailure():
        return const PasswordChangeOutcome.unknown();

      case AuthFormatFailure():
        return const PasswordChangeOutcome.failed(
          'サーバーでエラーが発生しました。\n'
          'しばらく待ってから、もう一度お試しください。',
        );

      case AuthApiFailure(:final code, :final message, :final fields):
        switch (code) {
          // 現在のパスワードの誤り（1〜4 回目）も、新しいパスワードの形式の誤りも、
          // 400 の fields で返る（ADR 0014）。欄の直下に出す。
          case 'validation_error':
            return _invalidFromFields(fields, message);

          case 'account_locked':
            return PasswordChangeOutcome.locked(message);

          case 'unauthenticated':
            return const PasswordChangeOutcome.unauthenticated();

          default:
            return PasswordChangeOutcome.failed(message);
        }
    }
  }

  /// API が返した検証エラーの内訳を、入力項目ごとのエラーへ振り分ける。
  PasswordChangeOutcome _invalidFromFields(
    Map<String, String> fields,
    String message,
  ) {
    final errors = <PasswordChangeField, String>{};
    var hasUnknownField = false;

    for (final entry in fields.entries) {
      final field = PasswordChangeField.fromApiField(entry.key);
      if (field == null) {
        hasUnknownField = true;
      } else {
        errors[field] = entry.value;
      }
    }

    state = state.copyWith(errors: errors);
    return PasswordChangeOutcome.invalid(
      alertMessage: hasUnknownField ? message : null,
    );
  }
}
