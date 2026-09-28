/// ユーザーの入力フォームが持つ入力項目。
///
/// 検証エラーの対応先をこの enum で表す。API は項目を `"name"` のような文字列で
/// 返すが、画面には API に存在しない項目（確認用パスワード）もあるため、画面側の
/// 項目をこちらで定義し、API の文字列からは [fromApiField] で変換する。
///
/// 宣言の順序は画面に並ぶ順序でもある。検証エラーが出たときは、この順に見て
/// 最初に該当した欄へフォーカスを移す。
enum UserFormField {
  name('name'),
  email('email'),
  password('password'),

  /// 確認用パスワード。入力の一致を確かめるためだけの欄で、API には送らない。
  passwordConfirmation(null);

  const UserFormField(this.apiField);

  /// API がこの項目を指すときに使う文字列。API に存在しない項目は `null`。
  final String? apiField;

  /// API が返した項目名を、画面の入力項目へ変換する。
  ///
  /// 対応する項目がなければ `null` を返す。呼び出し側は、`null` になった項目を
  /// **捨てずにアラートダイアログへ回す**こと。捨てると、API はエラーを返して
  /// いるのに画面にはどこにも表示されないまま登録できない状態になる（ADR 0008）。
  static UserFormField? fromApiField(String value) {
    for (final field in UserFormField.values) {
      if (field.apiField == value) return field;
    }
    return null;
  }
}
