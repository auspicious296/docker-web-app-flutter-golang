import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/user.dart';
import '../../domain/models/users_page.dart';
import '../model/user_dto.dart';
import '../services/user_api_client.dart';

part 'user_repository.g.dart';

/// ユーザーを供給する Repository。
///
/// Service を呼んで DTO をドメインモデルへ変換する。日時の文字列を [DateTime] へ
/// 変換するのもここで、画面側は文字列を解釈しなくてよい状態を保つ。
class UserRepository {
  const UserRepository({required this.apiClient});

  final UserApiClient apiClient;

  /// ユーザー一覧を取得する。失敗した場合は `UserFailure` を投げる。
  Future<UsersPage> fetchUsers({
    required int page,
    required int perPage,
    required bool includeDeleted,
  }) async {
    final dto = await apiClient.fetchUsers(
      page: page,
      perPage: perPage,
      includeDeleted: includeDeleted,
    );

    return UsersPage(
      users: dto.users.map(_toUser).toList(),
      page: dto.page,
      perPage: dto.perPage,
      total: dto.total,
    );
  }

  /// ユーザーを 1 件取得する。失敗した場合は `UserFailure` を投げる。
  Future<User> fetchUser(int id) async => _toUser(await apiClient.fetchUser(id));

  /// ユーザーの名前とメールアドレスを更新し、更新後のユーザーを返す。
  ///
  /// 戻り値を持つのは、一覧がこの値で該当する 1 行だけを差し替えるためである
  /// （登録と違い、一覧を取り直さない）。
  Future<User> updateUser({
    required int id,
    required String name,
    required String email,
  }) async => _toUser(
    await apiClient.updateUser(id: id, name: name, email: email),
  );

  /// ユーザーを登録する。失敗した場合は `UserFailure` を投げる。
  ///
  /// 戻り値を持たないのは、登録したユーザーの内容を画面が使わないためで、
  /// DTO からドメインモデルへの変換も発生しない（ADR 0008）。
  Future<void> createUser({
    required String name,
    required String email,
    required String password,
  }) => apiClient.createUser(name: name, email: email, password: password);

  /// パスワードを上書きし、上書き後のユーザーを返す。
  ///
  /// 戻り値を持つのは、一覧がこの値で該当する 1 行だけを差し替えるためである。
  /// パスワードは一覧に表示されないが、`updated_at` が変わるため「更新日時」列が
  /// 古いまま残らないようにする必要がある。
  Future<User> resetPassword({
    required int id,
    required String password,
  }) async => _toUser(
    await apiClient.resetPassword(id: id, password: password),
  );

  /// ユーザーを論理削除し、削除後のユーザーを返す。
  ///
  /// 戻り値を持つのは、一覧が削除済みの行を表示している場合に、この値で該当する
  /// 1 行だけを差し替えるためである（削除日時と更新日時が入った表示になる）。
  /// 削除済みを表示していない場合は一覧から行が消えるため、一覧を取り直す。
  Future<User> deleteUser(int id) async => _toUser(await apiClient.deleteUser(id));

  /// アカウントロックを解除し、解除後のユーザーを返す。
  Future<User> unlockUser(int id) async => _toUser(await apiClient.unlockUser(id));

  /// DTO をドメインモデルへ変換する。
  ///
  /// API はオフセット付きの RFC 3339（`2026-09-21T11:36:00+09:00`）を返す。
  /// `DateTime.parse` はこれを UTC として解釈するため、表示する側で `toLocal()`
  /// してから整形する。
  User _toUser(UserDto dto) => User(
    id: dto.id,
    name: dto.name,
    email: dto.email,
    createdAt: DateTime.parse(dto.createdAt),
    updatedAt: DateTime.parse(dto.updatedAt),
    deletedAt: _parseNullable(dto.deletedAt),
    isLocked: dto.isLocked,
    lockedAt: _parseNullable(dto.lockedAt),
    failedLoginAttempts: dto.failedLoginAttempts,
    lastLoginAt: _parseNullable(dto.lastLoginAt),
  );

  DateTime? _parseNullable(String? value) =>
      value == null ? null : DateTime.parse(value);
}

@riverpod
UserRepository userRepository(Ref ref) =>
    UserRepository(apiClient: ref.watch(userApiClientProvider));
