import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/user_repository.dart';
import '../../../domain/models/user.dart';
import '../../../domain/models/user_failure.dart';
import '../../../domain/models/user_form_field.dart';
import '../../../domain/models/user_validation.dart';

part 'user_edit_view_model.freezed.dart';
part 'user_edit_view_model.g.dart';

/// ユーザー編集画面の状態。
///
/// 入力中の文字列はここに持たない（登録画面と同じ理由で、View が hooks で保持
/// する）。ただし**取得したユーザー**はここに持つ。入力欄の直上に出す元値の表示
/// と、「変更されていない」の判定の両方がこの値を必要とするためである。
@freezed
class UserEditState with _$UserEditState {
  const UserEditState({
    this.isLoading = false,
    this.errors = const {},
    this.original,
    this.isEdited = false,
    this.isCompleted = false,
  });

  /// API の応答を待っているか。`true` のあいだ画面全体をローダーが覆う。
  ///
  /// 画面を開いた直後の取得と、「更新する」を押した後の両方でこれが立つ。利用者
  /// から見れば「この画面が通信している」という 1 種類の合図になる。
  final bool isLoading;

  /// 入力項目ごとの検証エラー。エラーのある項目だけが入る。
  ///
  /// クライアント側の検証結果と、API が返した検証エラー（400 の `fields`）・
  /// メールアドレスの重複（409）が、区別なくここへ入る。
  final Map<UserFormField, String> errors;

  /// 取得したユーザー。取得が終わるまでは `null`。
  ///
  /// 入力欄を書き換えてもこの値は変わらない。各入力欄の直上に出す「編集前の値」
  /// の表示元であり、どのユーザーを編集しているのかを最後まで示す役目も持つ。
  final User? original;

  /// 入力が [original] と異なるか。
  ///
  /// 離脱確認（go_router の `onExit`）はルート側にあり、View が hooks で持つ
  /// 入力値に手が届かない。そのため真偽値だけをここへ置き、View が各欄の
  /// `onChanged` から更新する。登録画面の `hasInput` と同じ仕組みだが、判定は
  /// 「文字があるか」ではなく「元の値と違うか」である。編集画面は最初から値が
  /// 入っているため、「文字があるか」では常に真になってしまう。
  final bool isEdited;

  /// 離脱確認を出さずに画面を離れてよい状態か。
  ///
  /// 更新が完了したとき（編集内容は保存済みで、破棄するものがない）と、画面を
  /// 閉じることが決まったとき（取得の失敗・404・成否不明）に `true` になる。
  final bool isCompleted;
}

/// 更新処理の結果。View はこれを見て、出すダイアログと次の操作を決める。
@freezed
sealed class UserEditOutcome with _$UserEditOutcome {
  /// 更新できた。完了のダイアログを出し、OK で一覧へ戻って [updated] の行を
  /// 差し替える。一覧は取り直さない。
  const factory UserEditOutcome.success(User updated) = UserEditSuccess;

  /// 入力が元の値と同じだった。通信は行っていない。
  ///
  /// アラートで知らせて画面に留まる。検証よりも先に判定するため、この結果が
  /// 返るとき [UserEditState.errors] は必ず空になる。
  const factory UserEditOutcome.notEdited() = UserEditNotEdited;

  /// 入力に誤りがある。エラーは [UserEditState.errors] に入っている。
  ///
  /// [alertMessage] は、API が返した検証エラーのうち画面の入力項目へ変換
  /// できなかったものがあった場合にだけ入る（ADR 0008）。
  const factory UserEditOutcome.invalid({String? alertMessage}) =
      UserEditInvalid;

  /// 更新できなかった。アラートを出し、画面には留まる。
  const factory UserEditOutcome.failed(String message) = UserEditFailed;

  /// 対象のユーザーが存在しない（404）。
  ///
  /// 画面を開いた後に別の経路で削除された場合に起きる。手元の一覧が実態とずれて
  /// いることが確定しているため、アラートの後は一覧へ戻って取り直す。
  const factory UserEditOutcome.gone(String message) = UserEditGone;

  /// 更新できたかどうか分からない。アラートを出し、OK で一覧へ戻って取り直す。
  const factory UserEditOutcome.unknown() = UserEditUnknown;
}

/// 編集画面が一覧へ返す結果。
///
/// 何も返さない（`null`）場合、一覧は何もしない。「戻る」で離脱したときと、
/// 取得に失敗して閉じたときがこれにあたり、一覧の表示も行の選択もそのまま残る。
@freezed
sealed class UserEditResult with _$UserEditResult {
  /// 更新できた。一覧はこのユーザーで該当する 1 行だけを差し替える。
  const factory UserEditResult.updated(User user) = UserEditUpdated;

  /// 一覧の内容が実態とずれている。一覧は取り直す。
  const factory UserEditResult.reloadNeeded() = UserEditReloadNeeded;
}

/// ユーザー編集画面の ViewModel。
///
/// 編集対象の ID を引数に取るため family になる（`userEditViewModelProvider(id)`）。
/// autoDispose のため画面を離れると状態は破棄され、別のユーザーを続けて編集しても
/// 前の値は残らない。
@riverpod
class UserEditViewModel extends _$UserEditViewModel {
  /// 依存する Repository。
  ///
  /// メソッドの中で `ref.read` せず、`build` で `ref.watch` して保持する
  /// （理由は `HealthViewModel` のコメントを参照）。
  late final UserRepository _repository;

  @override
  UserEditState build(int userId) {
    _repository = ref.watch(userRepositoryProvider);
    return const UserEditState();
  }

  /// 画面を開いたときに、編集対象のユーザーを取得する。
  ///
  /// 成功したら `null` を返し、[UserEditState.original] に値が入る。失敗したら
  /// その理由を返す。View はアラートを出してから画面を閉じる。
  Future<UserFailure?> load() async {
    if (state.isLoading) return null;

    state = state.copyWith(isLoading: true);
    try {
      final user = await _repository.fetchUser(userId);
      state = state.copyWith(original: user, isLoading: false);
      return null;
    } on UserFailure catch (failure) {
      // 取得に失敗した画面は閉じるため、離脱確認を出さない状態にしておく
      state = state.copyWith(isLoading: false, isCompleted: true);
      return failure;
    }
  }

  /// 入力が元の値と異なるかを更新する。View が各入力欄の `onChanged` から呼ぶ。
  ///
  /// 入力値を受け取るが**保持はしない**。判定結果の真偽値だけを状態に置くため、
  /// 値が変わらない限り再描画は起きない（freezed が生成する `==` による）。
  void syncEdited({required String name, required String email}) {
    final edited = _isEdited(name: name, email: email);
    if (state.isEdited == edited) return;
    state = state.copyWith(isEdited: edited);
  }

  /// 入力を検証し、通れば更新する。
  ///
  /// 「変更されていない」の判定を検証よりも**先**に置いている。元の値はサーバーが
  /// 受け付けた正規の値であり検証を必ず通るため順序による結果の差はないが、一度
  /// エラーを出した後に元の値へ戻して押した場合に、前回のエラー表示を消してから
  /// アラートを出す流れが素直になる。
  Future<UserEditOutcome> update({
    required String name,
    required String email,
  }) async {
    // 二重送信を防ぐ同期的なガード（登録画面と同じ理由）
    if (state.isLoading) return const UserEditOutcome.invalid();

    if (!_isEdited(name: name, email: email)) {
      state = state.copyWith(errors: const {});
      return const UserEditOutcome.notEdited();
    }

    final errors = validateUserForm(name: name, email: email);
    if (errors.isNotEmpty) {
      // 検証で弾いたので通信はしない
      state = state.copyWith(errors: errors);
      return const UserEditOutcome.invalid();
    }

    state = state.copyWith(errors: const {}, isLoading: true);
    try {
      final updated = await _repository.updateUser(
        id: userId,
        // 整形は Go 側でも行われるが、送る値と検証した値を一致させるため
        // ここでも同じ整形を通す。小文字化だけは Go 側に任せる。
        name: normalizeName(name),
        email: normalizeEmail(email),
      );
      state = state.copyWith(isLoading: false, isCompleted: true);
      return UserEditOutcome.success(updated);
    } on UserFailure catch (failure) {
      state = state.copyWith(isLoading: false);
      return _outcomeOf(failure);
    }
  }

  /// 入力が元の値と異なるか。
  ///
  /// 比較は**整形後の値**で行う（判定の基準を、実際にサーバーへ送る値に揃える）。
  /// 末尾に空白を足しただけ、全角スペースに変えただけなら「変更なし」になる。
  /// メールアドレスの大文字小文字は区別する。小文字化は Go 側に一本化しており、
  /// ここで無視すると画面に見えている文字列と判定が食い違うためである。
  ///
  /// 取得が終わっていなければ、比較する相手がないので常に `false` を返す。
  bool _isEdited({required String name, required String email}) {
    final original = state.original;
    if (original == null) return false;

    return normalizeName(name) != original.name ||
        normalizeEmail(email) != original.email;
  }

  /// 失敗の内訳を、画面が取るべき振る舞いへ変換する。
  UserEditOutcome _outcomeOf(UserFailure failure) {
    switch (failure) {
      case UserNetworkFailure():
        // リクエストが届いた後で切れた可能性があり、更新されたかどうかを
        // 画面から知る手段がない。一覧へ戻って取り直してもらう。
        state = state.copyWith(isCompleted: true);
        return const UserEditOutcome.unknown();

      case UserFormatFailure():
        return const UserEditOutcome.failed(
          'サーバーでエラーが発生しました。\n'
          'しばらく待ってから、もう一度お試しください。',
        );

      case UserApiFailure(:final code, :final message, :final fields):
        switch (code) {
          // 画面を開いた後に削除された。もう編集できないため画面を閉じる。
          case 'not_found':
            state = state.copyWith(isCompleted: true);
            return UserEditOutcome.gone(message);

          // メールアドレスの重複はサーバーにしか判定できない。直すのは利用者な
          // ので、アラートではなくメールアドレス欄の直下に出す（ADR 0008）。
          // 自分自身は重複の判定から除外されるため、ここに来るのは他のユーザー
          // と衝突したときだけである。
          case 'email_already_exists':
          case 'email_belongs_to_deleted_user':
            state = state.copyWith(errors: {UserFormField.email: message});
            return const UserEditOutcome.invalid();

          // クライアント側の検証を通ったのにここへ来たということは、Dart 側と
          // Go 側のルールがずれている。内訳を該当する欄の直下に出す。
          case 'validation_error':
            return _invalidFromFields(fields, message);

          default:
            return UserEditOutcome.failed(message);
        }
    }
  }

  /// API が返した検証エラーの内訳を、入力項目ごとのエラーへ振り分ける。
  UserEditOutcome _invalidFromFields(
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
    // エラーが 1 つも表示されないまま更新できない状態になり得る。
    return UserEditOutcome.invalid(
      alertMessage: hasUnknownField ? message : null,
    );
  }
}
