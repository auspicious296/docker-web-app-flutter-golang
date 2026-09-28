import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../domain/models/auth_failure.dart';
import '../../../domain/models/current_user.dart';

part 'session_view_model.freezed.dart';
part 'session_view_model.g.dart';

/// ログイン中のユーザーと、マイページ・パスワード変更画面から離れるときの扱い。
///
/// マイページとパスワード変更画面の 2 つの画面が、タイトルバーの「ユーザー名」
/// ボタンに同じユーザーを表示するため、画面ごとの ViewModel ではなくここに持つ。
@freezed
class SessionState with _$SessionState {
  const SessionState({
    this.user,
    this.isLoading = false,
    this.allowSilentExit = false,
  });

  /// ログイン中のユーザー。取得が終わるまで・ログアウトした後は `null`。
  ///
  /// `null` のあいだ、「ユーザー名」ボタンは表示しない。
  final CurrentUser? user;

  /// API の応答を待っているか。`true` のあいだ画面全体をローダーが覆う。
  final bool isLoading;

  /// マイページ・パスワード変更画面から、確認を出さずに離れてよい状態か。
  ///
  /// マイページの離脱（「戻る」・ブラウザの戻る）はログアウトの確認を、パスワード
  /// 変更画面の離脱は入力内容の破棄の確認を出す（ADR 0015）。ログアウトの成功・
  /// 401・ロック・取得の失敗のように、**プログラムから画面を移すとき**は、確認を
  /// 出す理由がないため、これを立ててから移る。ルートの `onExit` がこれを見る。
  final bool allowSilentExit;
}

/// ログアウトの結果。
@freezed
sealed class LogoutOutcome with _$LogoutOutcome {
  /// ログアウトできた。
  const factory LogoutOutcome.success() = LogoutSuccess;

  /// ログイン状態が切れていた（401）。「ログイン状態が切れました」のアラートの後、
  /// ログイン画面へ移る（ADR 0015）。
  const factory LogoutOutcome.unauthenticated() = LogoutUnauthenticated;

  /// ログアウトできなかった。アラートを出し、元の画面に留まる。
  const factory LogoutOutcome.failed(String message) = LogoutFailed;
}

/// ログイン中のユーザーを持つ ViewModel。
///
/// マイページからパスワード変更画面へ移っても同じ値を使うため、画面に結び付けず
/// keepAlive にしている。
@Riverpod(keepAlive: true)
class SessionViewModel extends _$SessionViewModel {
  late final AuthRepository _repository;

  @override
  SessionState build() {
    _repository = ref.watch(authRepositoryProvider);
    return const SessionState();
  }

  /// マイページを開いたときに、ログイン中のユーザーを取得する。
  ///
  /// 成功したら `null` を返す。失敗したらその理由を返し、画面はダイアログを出さず
  /// にログイン画面へ（401）、またはアラートの後にホーム画面へ（それ以外）移る。
  /// どちらもプログラムから画面を移すため、[SessionState.allowSilentExit] を立てる。
  Future<AuthFailure?> load() async {
    if (state.isLoading) return null;

    state = state.copyWith(isLoading: true, allowSilentExit: false);
    try {
      final user = await _repository.fetchMe();
      state = state.copyWith(user: user, isLoading: false);
      return null;
    } on AuthFailure catch (failure) {
      state = state.copyWith(
        user: null,
        isLoading: false,
        allowSilentExit: true,
      );
      return failure;
    }
  }

  /// ログアウトする。
  Future<LogoutOutcome> logout() async {
    if (state.isLoading) {
      return const LogoutOutcome.failed('ログアウトの処理中です。');
    }

    state = state.copyWith(isLoading: true);
    try {
      await _repository.logout();
      signedOut();
      return const LogoutOutcome.success();
    } on AuthFailure catch (failure) {
      state = state.copyWith(isLoading: false);
      if (failure.isUnauthenticated) {
        signedOut();
        return const LogoutOutcome.unauthenticated();
      }
      return LogoutOutcome.failed(switch (failure) {
        AuthNetworkFailure() => 'サーバーに接続できませんでした。\nもう一度お試しください。',
        AuthFormatFailure() =>
          'サーバーでエラーが発生しました。\n'
              'しばらく待ってから、もう一度お試しください。',
        AuthApiFailure(:final message) => message,
      });
    }
  }

  /// ログイン状態でなくなったことを記録し、確認を出さずに画面を離れられるようにする。
  ///
  /// ログアウトのほか、パスワード変更で 401 やロック（403 `account_locked`）が
  /// 返ったときに、ログイン画面へ移る前に呼ぶ。
  void signedOut() {
    state = state.copyWith(user: null, isLoading: false, allowSilentExit: true);
  }
}
