import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/user_repository.dart';
import '../../../domain/models/user.dart';
import '../../../domain/models/user_failure.dart';

part 'users_view_model.freezed.dart';
part 'users_view_model.g.dart';

/// ユーザー一覧画面の状態。
///
/// 疎通確認画面（`HealthState`）は 4 つの状態を sealed class で排他的に表して
/// いるが、この画面では**通信の状態と、選択行・ページ番号・表示条件が独立して
/// いる**ため、その形が当てはまらない。通信中もローダーが画面を覆うだけで前の
/// データは残り、ロック解除の後も選択は維持される。sealed class にすると、状態
/// が遷移するたびにこれらの値を詰め替えることになるため、単一のクラスにまとめて
/// いる。
@freezed
class UsersState with _$UsersState {
  const UsersState({
    this.users = const [],
    this.page = 1,
    this.perPage = 20,
    this.total = 0,
    this.includeDeleted = false,
    this.selectedUserId,
    this.isLoading = false,
    this.loadFailure,
  });

  /// 表示中のページに含まれるユーザー。
  final List<User> users;

  /// 表示中のページ番号（1 起点）。
  final int page;

  /// 1 ページあたりの行数。
  final int perPage;

  /// 条件に一致するユーザーの総数。
  final int total;

  /// 削除済みのユーザーも一覧に含めるか。
  final bool includeDeleted;

  /// 選択中の行のユーザー ID。未選択なら `null`。
  ///
  /// ユーザーそのものではなく ID を持つのは、ロック解除で [users] の中身を差し
  /// 替えても選択が追従するようにするため。
  final int? selectedUserId;

  /// API の応答を待っているか。`true` のあいだ画面全体をローダーが覆う。
  final bool isLoading;

  /// 一覧の取得に失敗した理由。成功していれば `null`。
  ///
  /// ロック解除の失敗はここに入れない。ロック解除が失敗しても一覧の内容は有効な
  /// ままで、画面全体を操作不能にする必要がないため。
  final UserFailure? loadFailure;

  /// 選択中のユーザー。選択が表示中のページに存在しなければ `null`。
  User? get selectedUser {
    final id = selectedUserId;
    if (id == null) return null;
    for (final user in users) {
      if (user.id == id) return user;
    }
    return null;
  }

  /// 「編集」「パスワードリセット」「削除」を押せるか。
  ///
  /// 削除済みのユーザーに対する更新系は API が 404 を返すため、選択できても
  /// ボタンは無効にして、404 に当たること自体を防ぐ。
  bool get canOperateSelected {
    final user = selectedUser;
    return user != null && !user.isDeleted;
  }

  /// 「アカウントロック解除」を押せるか。
  bool get canUnlock {
    final user = selectedUser;
    return user != null && !user.isDeleted && user.isLocked;
  }

  /// 「新規登録」を押せるか。一覧の取得に失敗している間は押せない。
  bool get canCreate => loadFailure == null;

  /// 総ページ数。0 件のときも 1 ページとして扱う（ページ送りの表示を壊さないため）。
  int get totalPages => total <= 0 ? 1 : (total + perPage - 1) ~/ perPage;

  bool get isFirstPage => page <= 1;

  bool get isLastPage => page >= totalPages;

  /// 表示中の範囲の先頭（1 起点）。0 件なら 0。
  int get firstRowNumber => total <= 0 ? 0 : (page - 1) * perPage + 1;

  /// 表示中の範囲の末尾。0 件なら 0。
  int get lastRowNumber => total <= 0 ? 0 : (page - 1) * perPage + users.length;
}

/// ユーザー一覧画面の ViewModel。
///
/// 通信を伴うメソッドは、失敗した理由を戻り値で返す。View はその戻り値を見て
/// アラートダイアログを出す。状態に残る [UsersState.loadFailure] を監視する形に
/// しないのは、同じ失敗が 2 回続いたときに状態が変化せず、検知できないため。
@riverpod
class UsersViewModel extends _$UsersViewModel {
  /// 依存する Repository。
  ///
  /// メソッドの中で `ref.read` せず、`build` で `ref.watch` して保持する
  /// （理由は `HealthViewModel` のコメントを参照）。
  late final UserRepository _repository;

  @override
  UsersState build() {
    _repository = ref.watch(userRepositoryProvider);
    return const UsersState();
  }

  /// 現在の条件で一覧を取り直す。画面を開いたときと「一覧再読み込み」で呼ぶ。
  Future<UserFailure?> load() =>
      _load(page: state.page, includeDeleted: state.includeDeleted);

  /// 指定したページを取得する。
  Future<UserFailure?> goToPage(int page) =>
      _load(page: page, includeDeleted: state.includeDeleted);

  /// 「削除済みも表示」を切り替えて取得し直す。
  ///
  /// 表示条件が変わると総件数も変わるため、ページは 1 に戻す。
  Future<UserFailure?> setIncludeDeleted({required bool includeDeleted}) =>
      _load(page: 1, includeDeleted: includeDeleted);

  /// 行の選択を切り替える。同じ行を再度タップすると選択を解除する。
  void toggleSelection(int userId) {
    state = state.copyWith(
      selectedUserId: state.selectedUserId == userId ? null : userId,
    );
  }

  /// 一覧の中の 1 行だけを、渡されたユーザーで差し替える。
  ///
  /// 更新系はすべて更新後のユーザーを返す規約（ADR 0004）を活かし、一覧を取り
  /// 直さずに表示を最新にするための入り口。ページ・表示条件・行の選択のいずれも
  /// 変えない。一覧の並びは `ORDER BY id` のため、名前やメールアドレスが変わって
  /// も行の位置は動かない。
  ///
  /// 表示中のページに該当する行がなければ何もしない。
  void replaceUser(User updated) {
    state = state.copyWith(
      users: [
        for (final user in state.users)
          if (user.id == updated.id) updated else user,
      ],
    );
  }

  /// 選択中のユーザーのアカウントロックを解除する。
  ///
  /// 成功したら、API が返した解除後のユーザーでその 1 行だけを差し替える。
  /// 一覧を取り直さないため、選択はそのまま維持される。
  Future<UserFailure?> unlockSelected() async {
    final target = state.selectedUser;
    if (target == null || state.isLoading) return null;

    state = state.copyWith(isLoading: true);
    try {
      final updated = await _repository.unlockUser(target.id);
      replaceUser(updated);
      state = state.copyWith(isLoading: false);
      return null;
    } on UserFailure catch (failure) {
      // 一覧の内容は有効なままなので loadFailure には入れない
      state = state.copyWith(isLoading: false);
      return failure;
    }
  }

  /// 一覧を取得して状態に反映する。
  ///
  /// 成功・失敗のどちらでも**選択は解除する**。一覧の中身が入れ替わるため、
  /// 画面に見えていない行が選択されたままになるのを防ぐ。
  ///
  /// 取得結果が空でページ番号が古くなっていた場合は、1 つ前のページを読み直す
  /// （判定の詳細は下のコメントを参照）。2 回目の通信も同じローダーの下で完結する。
  Future<UserFailure?> _load({
    required int page,
    required bool includeDeleted,
  }) async {
    if (state.isLoading) return null;

    state = state.copyWith(isLoading: true);
    try {
      var result = await _repository.fetchUsers(
        page: page,
        perPage: state.perPage,
        includeDeleted: includeDeleted,
      );

      // 取得結果が 0 件なのに総件数が残っている場合、ページ番号が古くなっている。
      // そのページの最後の 1 件が削除されたときに起きる（削除は、この画面で唯一
      // 総件数が減る操作である）。そのまま反映すると、テーブルが空なのに
      // 「20 件中 21〜20 件」という壊れた件数表示になる。
      //
      // 総件数が 0 のとき（全員が削除された）は何もしない。既存の「0 件」
      // 「該当するユーザーがいません」の表示がそのまま正しいためである。
      // 1 ページ目でも何もしない。0 ページ目を要求しないための歯止めでもある。
      //
      // 読み直しは 1 回だけとする。削除は 1 件ずつの操作のため、ずれるのは
      // 最大 1 ページである。
      if (result.users.isEmpty && result.total > 0 && page > 1) {
        result = await _repository.fetchUsers(
          page: page - 1,
          perPage: state.perPage,
          includeDeleted: includeDeleted,
        );
      }

      state = state.copyWith(
        users: result.users,
        page: result.page,
        total: result.total,
        includeDeleted: includeDeleted,
        selectedUserId: null,
        isLoading: false,
        loadFailure: null,
      );
      return null;
    } on UserFailure catch (failure) {
      // 失敗したときはテーブルを空にする。ページと表示条件は試みた値を保持し、
      // 「一覧再読み込み」で同じ条件をそのまま再試行できるようにする。
      state = state.copyWith(
        users: const [],
        page: page,
        total: 0,
        includeDeleted: includeDeleted,
        selectedUserId: null,
        isLoading: false,
        loadFailure: failure,
      );
      return failure;
    }
  }
}
