import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/user_repository.dart';
import '../../../domain/models/user.dart';
import '../../../domain/models/user_failure.dart';
import '../../../domain/models/user_form_field.dart';
import '../../../domain/models/user_validation.dart';

part 'user_password_reset_view_model.freezed.dart';
part 'user_password_reset_view_model.g.dart';

/// パスワードリセット画面の状態。
///
/// 入力中のパスワードはここに持たない（登録画面と同じ理由で、View が hooks で
/// 保持する）。取得したユーザーはここに持つ。ユーザー名とメールアドレスの表示と、
/// 完了ダイアログにロックの一文を足すかの判定に使うためである。
@freezed
class UserPasswordResetState with _$UserPasswordResetState {
  const UserPasswordResetState({
    this.isLoading = false,
    this.errors = const {},
    this.target,
    this.hasInput = false,
    this.isCompleted = false,
    this.updatedUser,
    this.needsListReload = false,
  });

  /// API の応答を待っているか。`true` のあいだ画面全体をローダーが覆う。
  final bool isLoading;

  /// 入力項目ごとの検証エラー。エラーのある項目だけが入る。
  ///
  /// この画面の入力欄はパスワードの 2 欄だけなので、ここに入るのもその 2 つと、
  /// API が返した検証エラー（400 の `fields` の `password`）に限られる。
  final Map<UserFormField, String> errors;

  /// リセット対象のユーザー。取得が終わるまでは `null`。
  ///
  /// ユーザー名とメールアドレスをテキストで表示するために使う。入力欄には何も
  /// 埋め込まない（API は `password_hash` を返さないため、埋め込む値がない）。
  final User? target;

  /// パスワードの 2 欄のいずれかに文字があるか。
  ///
  /// 離脱確認（go_router の `onExit`）はルート側にあり、View が hooks で持つ入力値
  /// に手が届かない。判定は登録画面の `hasInput` と同じで、この画面は入力欄に初期値
  /// がないためそのまま使える（編集画面が「元の値と異なるか」に変えたのは、取得した
  /// 値が最初から入っているためである）。
  final bool hasInput;

  /// 離脱確認を出さずに画面を離れてよい状態か。
  ///
  /// リセットが完了したとき（入力内容は反映済みで、破棄するものがない）と、画面を
  /// 閉じることが決まったとき（取得の失敗・404）に `true` になる。
  ///
  /// **成否不明のときは `true` にしない。** 画面に留まって押し直せるようにするため
  /// で、そこから「戻る」を押した場合は入力を守るために確認を出す。
  final bool isCompleted;

  /// リセットに成功したときの、更新後のユーザー。
  ///
  /// [needsListReload] と合わせて「画面を離れるときに一覧へ出す指示」を表す。
  /// 値が入っていれば、一覧はこのユーザーでその 1 行だけを差し替える。
  final User? updatedUser;

  /// 一覧を取り直す必要があるか。
  ///
  /// 成否不明（更新されたか分からない）と 404（手元の一覧が実態とずれている）で
  /// `true` になる。押し直して成功した場合は [updatedUser] が入り、こちらは
  /// `false` に下りる。差し替えで一覧が正しくなるため、取り直す必要がなくなる。
  final bool needsListReload;
}

/// リセット処理の結果。View はこれを見て、出すダイアログと次の操作を決める。
@freezed
sealed class UserPasswordResetOutcome with _$UserPasswordResetOutcome {
  /// リセットできた。完了のダイアログを出し、OK で画面を閉じる。
  ///
  /// [updated] の `isLocked` が `true` なら、ダイアログに「ロックされたままです」
  /// の一文を赤で添える。取得時の値ではなく API が返した最新の値で判定する。
  const factory UserPasswordResetOutcome.success(User updated) =
      UserPasswordResetSuccess;

  /// 入力に誤りがある。エラーは [UserPasswordResetState.errors] に入っている。
  ///
  /// [alertMessage] は、API が返した検証エラーのうち画面の入力項目へ変換
  /// できなかったものがあった場合にだけ入る（ADR 0008）。
  const factory UserPasswordResetOutcome.invalid({String? alertMessage}) =
      UserPasswordResetInvalid;

  /// リセットできなかった。アラートを出し、画面には留まる。
  const factory UserPasswordResetOutcome.failed(String message) =
      UserPasswordResetFailed;

  /// 対象のユーザーが存在しない（404）。アラートの後、画面を閉じる。
  const factory UserPasswordResetOutcome.gone(String message) =
      UserPasswordResetGone;

  /// リセットできたかどうか分からない。
  ///
  /// アラートを出すが**画面には留まる**。パスワードの上書きは何度実行しても結果が
  /// 同じなので、もう一度押すことが最も確実な確認手段になる。一覧に戻っても
  /// `password_hash` は表示されないため、目で確かめる手段がない。
  const factory UserPasswordResetOutcome.unknown() = UserPasswordResetUnknown;
}

/// パスワードリセット画面の ViewModel。
///
/// 対象の ID を引数に取るため family になる。autoDispose のため画面を離れると
/// 状態は破棄され、別のユーザーを続けて操作しても前の値は残らない。
@riverpod
class UserPasswordResetViewModel extends _$UserPasswordResetViewModel {
  /// 依存する Repository。
  ///
  /// メソッドの中で `ref.read` せず、`build` で `ref.watch` して保持する
  /// （理由は `HealthViewModel` のコメントを参照）。
  late final UserRepository _repository;

  @override
  UserPasswordResetState build(int userId) {
    _repository = ref.watch(userRepositoryProvider);
    return const UserPasswordResetState();
  }

  /// 画面を開いたときに、対象のユーザーを取得する。
  ///
  /// 編集画面の `load()` と同じ形。成功したら `null` を返し、失敗したらその理由を
  /// 返す。View はアラートを出してから画面を閉じる。
  Future<UserFailure?> load() async {
    if (state.isLoading) return null;

    state = state.copyWith(isLoading: true);
    try {
      final user = await _repository.fetchUser(userId);
      state = state.copyWith(target: user, isLoading: false);
      return null;
    } on UserFailure catch (failure) {
      // 取得に失敗した画面は閉じるため、離脱確認を出さない状態にしておく。
      // 一覧は何も変わっていないので needsListReload は立てない。
      state = state.copyWith(isLoading: false, isCompleted: true);
      return failure;
    }
  }

  /// 入力の有無を更新する。View が各入力欄の `onChanged` から呼ぶ。
  void setHasInput({required bool hasInput}) {
    if (state.hasInput == hasInput) return;
    state = state.copyWith(hasInput: hasInput);
  }

  /// 入力を検証し、通ればパスワードを上書きする。
  ///
  /// 検証は押すたびに最初からやり直す。前回のエラー表示は残さず、今回の入力だけで
  /// 判定し直した結果に置き換える。
  Future<UserPasswordResetOutcome> reset({
    required String password,
    required String passwordConfirmation,
  }) async {
    // 二重送信を防ぐ同期的なガード（登録画面と同じ理由）。成否不明のあと画面に
    // 留まって押し直せるため、この画面ではとくに効く。
    if (state.isLoading) return const UserPasswordResetOutcome.invalid();

    // ユーザー名とメールアドレスはこの画面に入力欄がないため渡さない
    final errors = validateUserForm(
      password: password,
      passwordConfirmation: passwordConfirmation,
    );
    if (errors.isNotEmpty) {
      // 検証で弾いたので通信はしない
      state = state.copyWith(errors: errors);
      return const UserPasswordResetOutcome.invalid();
    }

    state = state.copyWith(errors: const {}, isLoading: true);
    try {
      final updated = await _repository.resetPassword(
        id: userId,
        password: password,
      );
      // 成功したので、一覧は 1 行差し替えで正しくなる。過去に成否不明が起きて
      // needsListReload が立っていても、ここで下ろす（取り直しは不要になる）。
      state = state.copyWith(
        isLoading: false,
        isCompleted: true,
        updatedUser: updated,
        needsListReload: false,
      );
      return UserPasswordResetOutcome.success(updated);
    } on UserFailure catch (failure) {
      state = state.copyWith(isLoading: false);
      return _outcomeOf(failure);
    }
  }

  /// 失敗の内訳を、画面が取るべき振る舞いへ変換する。
  UserPasswordResetOutcome _outcomeOf(UserFailure failure) {
    switch (failure) {
      case UserNetworkFailure():
        // リクエストが届いた後で切れた可能性があり、上書きされたかどうかを画面から
        // 知る手段がない。パスワードの上書きは冪等なので、押し直せるように画面へ
        // 留まる（isCompleted は立てない）。離脱する時点で一覧を取り直す。
        state = state.copyWith(needsListReload: true);
        return const UserPasswordResetOutcome.unknown();

      case UserFormatFailure():
        return const UserPasswordResetOutcome.failed(
          'サーバーでエラーが発生しました。\n'
          'しばらく待ってから、もう一度お試しください。',
        );

      case UserApiFailure(:final code, :final message, :final fields):
        switch (code) {
          // 画面を開いた後に削除された。もう操作できないため画面を閉じ、手元の
          // 一覧が実態とずれていることが確定しているので取り直す。
          case 'not_found':
            state = state.copyWith(isCompleted: true, needsListReload: true);
            return UserPasswordResetOutcome.gone(message);

          // クライアント側の検証を通ったのにここへ来たということは、Dart 側と
          // Go 側のルールがずれている。内訳を該当する欄の直下に出す。
          case 'validation_error':
            return _invalidFromFields(fields, message);

          default:
            return UserPasswordResetOutcome.failed(message);
        }
    }
  }

  /// API が返した検証エラーの内訳を、入力項目ごとのエラーへ振り分ける。
  UserPasswordResetOutcome _invalidFromFields(
    Map<String, String> fields,
    String message,
  ) {
    final errors = <UserFormField, String>{};
    var hasUnknownField = false;

    for (final entry in fields.entries) {
      final field = UserFormField.fromApiField(entry.key);
      if (field == null) {
        hasUnknownField = true;
      } else {
        errors[field] = entry.value;
      }
    }

    state = state.copyWith(errors: errors);

    // 振り分けられなかった項目があれば、その分はアラートで知らせる。捨てると
    // エラーが 1 つも表示されないままリセットできない状態になり得る。
    return UserPasswordResetOutcome.invalid(
      alertMessage: hasUnknownField ? message : null,
    );
  }
}
