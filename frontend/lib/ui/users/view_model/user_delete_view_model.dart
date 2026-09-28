import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/user_repository.dart';
import '../../../domain/models/user.dart';
import '../../../domain/models/user_failure.dart';

part 'user_delete_view_model.freezed.dart';
part 'user_delete_view_model.g.dart';

/// 削除を実行するために入力する語。
///
/// 案内文・プレースホルダ・照合・エラー文言のすべてがこの 1 つを参照する。
/// 画面に表示する語と照合に使う語が食い違わないようにするためである。
const String kDeleteConfirmationKeyword = 'confirm';

/// 削除確認入力が誤っていたときに出す文言。
///
/// **未入力と誤入力で分けない。** どちらの場合も管理者がすべきことは
/// 「`confirm` と入力する」の 1 つで同じであり、文言を 2 種類にすると意味の
/// ない違いを探させることになるためである。
const String kDeleteConfirmationError = '「$kDeleteConfirmationKeyword」と入力してください';

/// ユーザー情報削除画面の状態。
///
/// 登録画面・パスワードリセット画面と比べて持つものが少ない。**離脱確認を出さない**
/// ため入力の有無（`hasInput`）と離脱可否（`isCompleted`）が不要で、一覧への指示を
/// `context.pop` の戻り値で返すため状態に持つ必要もないからである。
///
/// 入力中の文字列はここに持たない（登録画面と同じ理由で、View が hooks で保持する）。
@freezed
class UserDeleteState with _$UserDeleteState {
  const UserDeleteState({
    this.isLoading = false,
    this.target,
    this.confirmationError,
  });

  /// API の応答を待っているか。`true` のあいだ画面全体をローダーが覆う。
  final bool isLoading;

  /// 削除対象のユーザー。取得が終わるまでは `null`。
  ///
  /// ユーザー名とメールアドレスをテキストで表示するために使う。
  final User? target;

  /// 削除確認入力の検証エラー。エラーがなければ `null`。
  ///
  /// 他の 3 画面は `Map<UserFormField, String>` で持っているが、この画面は
  /// **文字列 1 つで持つ**。あの形が必要なのは「API が返した複数の検証エラーを、
  /// どの欄の下に出すか振り分ける」ためであり、`DELETE` はボディを送らないので
  /// API が検証エラーを返す経路が存在せず、欄も 1 つしかないためである。
  final String? confirmationError;
}

/// 削除処理の結果。View はこれを見て、出すダイアログと次の操作を決める。
@freezed
sealed class UserDeleteOutcome with _$UserDeleteOutcome {
  /// 削除できた。完了のダイアログを出し、OK で画面を閉じる。
  ///
  /// [deleted] は `deleted_at` が入った削除後のユーザー。一覧が削除済みを表示中
  /// なら、この値でその 1 行だけを差し替える。
  const factory UserDeleteOutcome.success(User deleted) = UserDeleteSuccess;

  /// 対象のユーザーがすでに削除されている（404）。
  ///
  /// **失敗としては扱わない。** 管理者が望んだ状態（そのユーザーが削除されている）
  /// はすでに成立しているためで、ロック解除がすでに解除済みでもエラーにしない
  /// （ADR 0004）のと同じ考え方である。アラートの後、画面を閉じる。
  const factory UserDeleteOutcome.gone() = UserDeleteGone;

  /// 削除できたかどうか分からない。アラートの後、画面を閉じる。
  ///
  /// パスワードリセットは冪等なので画面に留まって押し直させたが（ADR 0010）、
  /// **削除は冪等ではない**。実際には成功していた場合、押し直すと 404 が返り
  /// 「削除に失敗しました」と誤解させることになる。一覧へ戻れば、削除済みの
  /// 表示か行の有無で管理者が自分の目で確かめられる。
  const factory UserDeleteOutcome.unknown() = UserDeleteUnknown;

  /// 削除できなかった。アラートを出し、画面には留まる。
  const factory UserDeleteOutcome.failed(String message) = UserDeleteFailed;
}

/// 画面を閉じるときに一覧へ返す指示。
///
/// 編集画面の `UserEditResult` と同じ形。削除画面は成功・404・成否不明のいずれでも
/// 自分で `context.pop` を呼ぶため、ブラウザの戻るボタンだけを通る経路が存在せず、
/// パスワードリセット画面のように `onExit` へ寄せる必要がない。
@freezed
sealed class UserDeleteResult with _$UserDeleteResult {
  /// 削除できた。一覧は「削除済みも表示」の状態を見て、1 行差し替えか取り直しかを
  /// 選ぶ。
  const factory UserDeleteResult.deleted(User user) = UserDeleteDeleted;

  /// 一覧が実態とずれている可能性がある。一覧は取り直す。
  const factory UserDeleteResult.reloadNeeded() = UserDeleteReloadNeeded;
}

/// ユーザー情報削除画面の ViewModel。
///
/// 対象の ID を引数に取るため family になる。autoDispose のため画面を離れると
/// 状態は破棄され、別のユーザーを続けて操作しても前の値は残らない。
@riverpod
class UserDeleteViewModel extends _$UserDeleteViewModel {
  /// 依存する Repository。
  ///
  /// メソッドの中で `ref.read` せず、`build` で `ref.watch` して保持する
  /// （理由は `HealthViewModel` のコメントを参照）。
  late final UserRepository _repository;

  @override
  UserDeleteState build(int userId) {
    _repository = ref.watch(userRepositoryProvider);
    return const UserDeleteState();
  }

  /// 画面を開いたときに、対象のユーザーを取得する。
  ///
  /// 編集画面・パスワードリセット画面の `load()` と同じ形。成功したら `null` を
  /// 返し、失敗したらその理由を返す。View はアラートを出してから画面を閉じる。
  Future<UserFailure?> load() async {
    if (state.isLoading) return null;

    state = state.copyWith(isLoading: true);
    try {
      final user = await _repository.fetchUser(userId);
      state = state.copyWith(target: user, isLoading: false);
      return null;
    } on UserFailure catch (failure) {
      state = state.copyWith(isLoading: false);
      return failure;
    }
  }

  /// 削除確認入力を照合する。通れば `true`、誤りがあれば `false` を返す。
  ///
  /// [delete] と分けているのは、**この 2 つの間に確認ダイアログが入る**ため。
  /// 照合を通った場合だけダイアログを出し、「はい」で [delete] を呼ぶ。
  ///
  /// 前後の空白を除いてから完全一致で判定する。大文字・小文字は区別する。
  /// 空白を救うのは**目に見えない差異**だからで、画面上は指示どおりに見えるのに
  /// 通らない状態を作らないためである。大文字は入力欄を見れば分かるため救わない。
  ///
  /// `trim()` が除くのは Unicode の空白すべてで、全角スペース（U+3000）・タブ・
  /// 連続した空白・BOM も含まれる。途中の空白は除かないため `con firm` は通らない。
  bool validate(String confirmation) {
    if (confirmation.trim() == kDeleteConfirmationKeyword) {
      state = state.copyWith(confirmationError: null);
      return true;
    }

    state = state.copyWith(confirmationError: kDeleteConfirmationError);
    return false;
  }

  /// ユーザーを削除する。検証は [validate] で済んでいる前提で呼ぶ。
  ///
  /// 二重送信のガードに引っかかった場合だけ `null` を返す。View は何もしない
  /// （すでに走っている 1 回目の結果がダイアログを出すため）。
  Future<UserDeleteOutcome?> delete() async {
    // 二重送信を防ぐ同期的なガード（登録画面と同じ理由）。ボタンの無効化も
    // ローダーの表示も次のフレームを待つため、その 1 フレームのあいだは連打が
    // 素通りする。このガードは同期的に効く。
    if (state.isLoading) return null;

    state = state.copyWith(isLoading: true);
    try {
      final deleted = await _repository.deleteUser(userId);
      state = state.copyWith(isLoading: false);
      return UserDeleteOutcome.success(deleted);
    } on UserFailure catch (failure) {
      state = state.copyWith(isLoading: false);
      return _outcomeOf(failure);
    }
  }

  /// 失敗の内訳を、画面が取るべき振る舞いへ変換する。
  UserDeleteOutcome _outcomeOf(UserFailure failure) => switch (failure) {
    // リクエストが届いた後で切れた可能性があり、削除されたかを画面から知る手段が
    // ない。押し直しは 404 を招くだけなので、一覧へ戻って目で確かめてもらう。
    UserNetworkFailure() => const UserDeleteOutcome.unknown(),

    UserFormatFailure() => const UserDeleteOutcome.failed(
      'サーバーでエラーが発生しました。\n'
      'しばらく待ってから、もう一度お試しください。',
    ),

    // 画面を開いた後に、別の管理者が削除した。望む状態は成立しているため、
    // 失敗ではなく「すでに削除済み」として扱う。
    UserApiFailure(code: 'not_found') => const UserDeleteOutcome.gone(),

    UserApiFailure(:final message) => UserDeleteOutcome.failed(message),
  };
}
