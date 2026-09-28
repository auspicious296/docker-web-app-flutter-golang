import 'auth_form_field.dart';
import 'user_form_field.dart';
import 'user_validation.dart';

/// ログイン画面の入力を検証し、項目ごとのエラー文言を返す。戻り値が空なら誤りはない。
///
/// 検証は「空かどうか」だけで、登録時の形式の規則は使わない（ADR 0014）。規則を
/// 後から狭めたときに、古い規則で登録したユーザーがログインできなくなるためである。
/// メールアドレスは、API と同じく前後の空白を除いてから判定する。
Map<LoginField, String> validateLoginForm({
  required String email,
  required String password,
}) {
  return {
    if (normalizeEmail(email).isEmpty) LoginField.email: 'メールアドレスを入力してください',
    if (password.isEmpty) LoginField.password: 'パスワードを入力してください',
  };
}

/// パスワード変更画面の入力を検証し、項目ごとのエラー文言を返す。
///
/// 現在のパスワードは「空かどうか」だけを見る（照合は API が行う）。新しい
/// パスワードと確認用は、登録画面・パスワードリセット画面と同じ規則
/// （[validateUserForm]）で検証し、項目を付け替える。空のときの文言だけは、API の
/// `new_password` の文言（「新しいパスワードを入力してください」）に揃える。
Map<PasswordChangeField, String> validatePasswordChangeForm({
  required String currentPassword,
  required String newPassword,
  required String newPasswordConfirmation,
}) {
  final userErrors = validateUserForm(
    password: newPassword,
    passwordConfirmation: newPasswordConfirmation,
  );

  return {
    if (currentPassword.isEmpty)
      PasswordChangeField.currentPassword: '現在のパスワードを入力してください',
    if (newPassword.isEmpty)
      PasswordChangeField.newPassword: '新しいパスワードを入力してください'
    else
      PasswordChangeField.newPassword: ?userErrors[UserFormField.password],
    PasswordChangeField.newPasswordConfirmation:
        ?userErrors[UserFormField.passwordConfirmation],
  };
}
