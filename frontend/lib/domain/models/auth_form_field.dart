/// ログイン画面の入力項目。
///
/// 宣言の順序は画面に並ぶ順序でもある。検証エラーが出たときは、この順に見て
/// 最初に該当した欄へフォーカスを移す。
enum LoginField {
  email('email'),
  password('password');

  const LoginField(this.apiField);

  /// API がこの項目を指すときに使う文字列。
  final String apiField;

  /// API が返した項目名を、画面の入力項目へ変換する。対応する項目がなければ
  /// `null` を返す。`null` になった項目は捨てずにアラートへ回すこと（ADR 0008）。
  static LoginField? fromApiField(String value) {
    for (final field in LoginField.values) {
      if (field.apiField == value) return field;
    }
    return null;
  }
}

/// パスワード変更画面の入力項目。
///
/// 宣言の順序は画面に並ぶ順序でもある（[LoginField] と同じ）。
enum PasswordChangeField {
  currentPassword('current_password'),
  newPassword('new_password'),

  /// 新しいパスワードの確認用。入力の一致を確かめるためだけの欄で、API には送らない。
  newPasswordConfirmation(null);

  const PasswordChangeField(this.apiField);

  /// API がこの項目を指すときに使う文字列。API に存在しない項目は `null`。
  final String? apiField;

  /// 新しいパスワードの 2 欄（新しいパスワード・確認用）か。
  ///
  /// 入力エラーのときにクリアする欄の組を決めるのに使う（ADR 0015）。
  bool get isNewPasswordPair => this != currentPassword;

  /// API が返した項目名を、画面の入力項目へ変換する。対応する項目がなければ
  /// `null` を返す。
  static PasswordChangeField? fromApiField(String value) {
    for (final field in PasswordChangeField.values) {
      if (field.apiField == value) return field;
    }
    return null;
  }
}
