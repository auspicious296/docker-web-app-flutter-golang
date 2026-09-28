import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/user_repository.dart';
import '../../../domain/models/user_failure.dart';
import '../../../domain/models/user_form_field.dart';
import '../../../domain/models/user_validation.dart';

part 'user_create_view_model.freezed.dart';
part 'user_create_view_model.g.dart';

/// ユーザー新規登録画面の状態。
///
/// 入力中の文字列とパスワードの表示切り替えはここに持たない。登録ボタンを押す
/// 瞬間まで ViewModel が知る必要のない値で、1 文字ごとに状態を作り直す意味が
/// ないためである（View が hooks で保持する）。
@freezed
class UserCreateState with _$UserCreateState {
  const UserCreateState({
    this.isLoading = false,
    this.errors = const {},
    this.hasInput = false,
    this.isCompleted = false,
  });

  /// API の応答を待っているか。`true` のあいだ画面全体をローダーが覆う。
  final bool isLoading;

  /// 入力項目ごとの検証エラー。エラーのある項目だけが入る。
  ///
  /// クライアント側の検証結果と、API が返した検証エラー（400 の `fields`）・
  /// メールアドレスの重複（409）が、区別なくここへ入る。表示する側は、どちらが
  /// 入れたのかを気にしなくてよい。
  final Map<UserFormField, String> errors;

  /// 4 つの入力欄のいずれかに文字があるか。
  ///
  /// 離脱確認（go_router の `onExit`）はルート側にあり、View が hooks で持つ
  /// 入力値に手が届かない。そのため真偽値だけをここへ置き、View が各欄の
  /// `onChanged` から更新する。freezed が生成する `==` により、値が変わらない
  /// 限り再描画は起きない。
  final bool hasInput;

  /// 離脱確認を出さずに画面を離れてよい状態か。
  ///
  /// 登録が完了したとき（入力内容は登録済みで、破棄するものがない）と、成否不明
  /// のとき（一覧へ戻って確認してもらう）に `true` になる。
  final bool isCompleted;
}

/// 登録処理の結果。View はこれを見て、出すダイアログと次の操作を決める。
@freezed
sealed class UserCreateOutcome with _$UserCreateOutcome {
  /// 登録できた。完了のダイアログを出し、OK で一覧へ戻る。
  const factory UserCreateOutcome.success() = UserCreateSuccess;

  /// 入力に誤りがある。エラーは [UserCreateState.errors] に入っている。
  ///
  /// [alertMessage] は、API が返した検証エラーのうち画面の入力項目へ変換
  /// できなかったものがあった場合にだけ入る。捨てるとエラーがどこにも表示
  /// されないまま登録できない状態になるため、アラートで知らせる（ADR 0008）。
  const factory UserCreateOutcome.invalid({String? alertMessage}) =
      UserCreateInvalid;

  /// 登録できなかった。アラートを出し、画面には留まる。
  const factory UserCreateOutcome.failed(String message) = UserCreateFailed;

  /// 登録できたかどうか分からない。アラートを出し、OK で一覧へ戻って確認する。
  const factory UserCreateOutcome.unknown() = UserCreateUnknown;
}

/// ユーザー新規登録画面の ViewModel。
@riverpod
class UserCreateViewModel extends _$UserCreateViewModel {
  /// 依存する Repository。
  ///
  /// メソッドの中で `ref.read` せず、`build` で `ref.watch` して保持する
  /// （理由は `HealthViewModel` のコメントを参照）。
  late final UserRepository _repository;

  @override
  UserCreateState build() {
    _repository = ref.watch(userRepositoryProvider);
    return const UserCreateState();
  }

  /// 入力の有無を更新する。View が各入力欄の `onChanged` から呼ぶ。
  void setHasInput({required bool hasInput}) {
    if (state.hasInput == hasInput) return;
    state = state.copyWith(hasInput: hasInput);
  }

  /// 入力を検証し、通れば登録する。
  ///
  /// 検証は押すたびに最初からやり直す。前回のエラー表示は残さず、今回の入力
  /// だけで判定し直した結果に置き換える。
  Future<UserCreateOutcome> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    // 二重送信を防ぐのはこのガードだけである。ボタンの無効化もローダーの表示も
    // 次のフレームを待つため、その 1 フレームのあいだは連打が素通りする。この
    // ガードは同期的に効くため、2 回目の呼び出しは必ずここで戻る。
    if (state.isLoading) return const UserCreateOutcome.invalid();

    final errors = validateUserForm(
      name: name,
      email: email,
      password: password,
      passwordConfirmation: passwordConfirmation,
    );
    if (errors.isNotEmpty) {
      // 検証で弾いたので通信はしない
      state = state.copyWith(errors: errors);
      return const UserCreateOutcome.invalid();
    }

    state = state.copyWith(errors: const {}, isLoading: true);
    try {
      await _repository.createUser(
        // 整形は Go 側でも行われるが、送る値と検証した値を一致させるため
        // ここでも同じ整形を通す。小文字化だけは Go 側に任せる。
        name: normalizeName(name),
        email: normalizeEmail(email),
        password: password,
      );
      state = state.copyWith(isLoading: false, isCompleted: true);
      return const UserCreateOutcome.success();
    } on UserFailure catch (failure) {
      state = state.copyWith(isLoading: false);
      return _outcomeOf(failure);
    }
  }

  /// 失敗の内訳を、画面が取るべき振る舞いへ変換する。
  UserCreateOutcome _outcomeOf(UserFailure failure) {
    switch (failure) {
      case UserNetworkFailure():
        // リクエストが届いた後で切れた可能性があり、登録されたかどうかを
        // 画面から知る手段がない。一覧へ戻って確認してもらう。
        state = state.copyWith(isCompleted: true);
        return const UserCreateOutcome.unknown();

      case UserFormatFailure():
        return const UserCreateOutcome.failed(
          'サーバーでエラーが発生しました。\n'
          'しばらく待ってから、もう一度お試しください。',
        );

      case UserApiFailure(:final code, :final message, :final fields):
        switch (code) {
          // メールアドレスの重複はサーバーにしか判定できない。直すのは利用者な
          // ので、アラートではなくメールアドレス欄の直下に出す（ADR 0008）。
          case 'email_already_exists':
          case 'email_belongs_to_deleted_user':
            state = state.copyWith(
              errors: {UserFormField.email: message},
            );
            return const UserCreateOutcome.invalid();

          // クライアント側の検証を通ったのにここへ来たということは、Dart 側と
          // Go 側のルールがずれている。内訳を該当する欄の直下に出す。
          case 'validation_error':
            return _invalidFromFields(fields, message);

          default:
            return UserCreateOutcome.failed(message);
        }
    }
  }

  /// API が返した検証エラーの内訳を、入力項目ごとのエラーへ振り分ける。
  UserCreateOutcome _invalidFromFields(
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
    // エラーが 1 つも表示されないまま登録できない状態になり得る。
    return UserCreateOutcome.invalid(
      alertMessage: hasUnknownField ? message : null,
    );
  }
}
