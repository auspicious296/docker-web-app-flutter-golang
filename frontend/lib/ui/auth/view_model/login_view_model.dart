import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../domain/models/auth_failure.dart';
import '../../../domain/models/auth_form_field.dart';
import '../../../domain/models/auth_validation.dart';

part 'login_view_model.freezed.dart';
part 'login_view_model.g.dart';

/// ログイン画面の状態。
///
/// 入力中の値はここに持たない（登録画面と同じく View が hooks で保持する）。
@freezed
class LoginState with _$LoginState {
  const LoginState({this.isLoading = false, this.errors = const {}});

  /// API の応答を待っているか。`true` のあいだ画面全体をローダーが覆う。
  final bool isLoading;

  /// 入力項目ごとの検証エラー。エラーのある項目だけが入る。
  final Map<LoginField, String> errors;
}

/// ログイン処理の結果。View はこれを見て、出すダイアログと次の操作を決める。
@freezed
sealed class LoginOutcome with _$LoginOutcome {
  /// ログインできた。マイページへ移る。
  const factory LoginOutcome.success() = LoginSuccess;

  /// 入力に誤りがある。エラーは [LoginState.errors] に入っている。
  ///
  /// [alertMessage] は、API が返した検証エラーのうち画面の入力項目へ変換できな
  /// かったものがあった場合にだけ入る（ADR 0008）。
  const factory LoginOutcome.invalid({String? alertMessage}) = LoginInvalid;

  /// ログインできなかった。タイトル「ログインできませんでした」のアラートを出す。
  ///
  /// [clearPassword] が `true` のときは、パスワード欄だけをクリアする。401
  /// `invalid_credentials`（入力が誤っていた可能性がある）のときだけ `true` になる。
  /// 429 は、同じ IP アドレスを共有する他の利用者のあおりで、正しい入力でも拒否
  /// されるため、入力を変えない（ADR 0014・0015）。
  const factory LoginOutcome.failed(
    String message, {
    @Default(false) bool clearPassword,
  }) = LoginFailed;
}

/// ログイン画面の ViewModel。
@riverpod
class LoginViewModel extends _$LoginViewModel {
  /// 依存する Repository。
  ///
  /// メソッドの中で `ref.read` せず、`build` で `ref.watch` して保持する
  /// （理由は `HealthViewModel` のコメントを参照）。
  late final AuthRepository _repository;

  @override
  LoginState build() {
    _repository = ref.watch(authRepositoryProvider);
    return const LoginState();
  }

  /// 入力を検証し、通ればログインする。
  Future<LoginOutcome> login({
    required String email,
    required String password,
  }) async {
    // 二重送信を防ぐ同期的なガード（登録画面と同じ理由）
    if (state.isLoading) return const LoginOutcome.invalid();

    final errors = validateLoginForm(email: email, password: password);
    if (errors.isNotEmpty) {
      state = state.copyWith(errors: errors);
      return const LoginOutcome.invalid();
    }

    state = state.copyWith(errors: const {}, isLoading: true);
    try {
      // メールアドレスの前後の空白と大文字は API が整える（ADR 0014）
      await _repository.login(email: email, password: password);
      state = state.copyWith(isLoading: false);
      return const LoginOutcome.success();
    } on AuthFailure catch (failure) {
      state = state.copyWith(isLoading: false);
      return _outcomeOf(failure);
    }
  }

  /// 失敗の内訳を、画面が取るべき振る舞いへ変換する（ADR 0015）。
  LoginOutcome _outcomeOf(AuthFailure failure) {
    switch (failure) {
      case AuthNetworkFailure():
        // ログインは押し直しても問題がないため、入力を残して押し直しを促す
        return const LoginOutcome.failed('サーバーに接続できませんでした。\nもう一度お試しください。');

      case AuthFormatFailure():
        return const LoginOutcome.failed(
          'サーバーでエラーが発生しました。\n'
          'しばらく待ってから、もう一度お試しください。',
        );

      case AuthApiFailure(:final code, :final message, :final fields):
        switch (code) {
          case 'invalid_credentials':
            return LoginOutcome.failed(message, clearPassword: true);

          // クライアント側の検証を通ったのにここへ来たということは、Dart 側と
          // Go 側のルールがずれている。内訳を該当する欄の直下に出す。
          case 'validation_error':
            return _invalidFromFields(fields, message);

          // account_locked・too_many_requests・csrf_token_invalid など。
          // 入力が誤っていたとは限らないため、入力は変えない。
          default:
            return LoginOutcome.failed(message);
        }
    }
  }

  /// API が返した検証エラーの内訳を、入力項目ごとのエラーへ振り分ける。
  LoginOutcome _invalidFromFields(Map<String, String> fields, String message) {
    final errors = <LoginField, String>{};
    var hasUnknownField = false;

    for (final entry in fields.entries) {
      final field = LoginField.fromApiField(entry.key);
      if (field == null) {
        hasUnknownField = true;
      } else {
        errors[field] = entry.value;
      }
    }

    state = state.copyWith(errors: errors);
    return LoginOutcome.invalid(alertMessage: hasUnknownField ? message : null);
  }
}
