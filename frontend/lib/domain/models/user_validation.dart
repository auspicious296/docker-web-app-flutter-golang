import 'user_form_field.dart';

/// 入力値の制限。Go 側の `service/user.go` の定数と同じ値を持つ。
///
/// 同じルールが Dart と Go の 2 か所に存在するが、これは意図した二重化である。
/// クライアント側の検証は「送信前に分かる誤りを送信前に出す」ための先出しで、
/// 正しさの最後の拠り所はサーバーにある。ずれた場合はサーバーが 400 で弾き、
/// その内訳が同じ入力欄の直下に表示されるため、黙って通ることはない（ADR 0008）。
const int kMaxNameLength = 255;
const int kMaxEmailLength = 255;
const int kMinPasswordLength = 8;
const int kMaxPasswordLength = 72;

/// メールアドレスの形式。
///
/// Go 側は `net/mail` で解釈したうえで表示名付き（`山田 <a@example.com>`）を弾き、
/// ドメインにドットがあることを確かめている。Dart に `net/mail` 相当はないため、
/// ここでは「空白と @ を含まない文字列 + @ + 空白と @ を含まない文字列 + . +
/// 空白と @ を含まない文字列」で近似する。Go より緩いケースはサーバーが弾く。
final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// パスワードに使える文字（ASCII の印字可能文字。スペースを含まない）。
final RegExp _passwordPattern = RegExp(r'^[\x21-\x7E]+$');

/// ユーザー名を整形する。
///
/// 全角スペースを半角に置換したうえで前後の空白を除去する。Go 側の
/// `normalizeName` と同じ処理を送信前に行うことで、「全角スペースだけを入力」が
/// 未入力と判定されずに通過し、往復してから弾かれるのを防ぐ。
String normalizeName(String value) =>
    value.replaceAll('　', ' ').trim();

/// メールアドレスを整形する。
///
/// 前後の空白を除去するだけで、小文字への変換は行わない。小文字化は目に見える
/// 変化であり、利用者が入力した文字列と送る文字列が食い違うため、Go 側に一本化
/// している（ADR 0002）。
String normalizeEmail(String value) => value.trim();

/// ユーザーの入力フォームを検証し、項目ごとのエラー文言を返す。
///
/// 戻り値が空なら誤りはない。**欄ごとに最初に該当した 1 つだけ**を入れ、欄を
/// またいでは該当したものを全部入れる（Go 側の `validator` と同じ構造）。
///
/// [name] と [email] は整形前の値を渡してよい。この関数の中で整形してから
/// 判定する。[passwordConfirmation] を渡さない場合は確認用の判定を行わない
/// （パスワードリセット画面など、確認用の欄がない画面のため）。
Map<UserFormField, String> validateUserForm({
  String? name,
  String? email,
  String? password,
  String? passwordConfirmation,
}) {
  final errors = <UserFormField, String>{};

  if (name != null) {
    final value = normalizeName(name);
    if (value.isEmpty) {
      errors[UserFormField.name] = '名前を入力してください';
    } else if (value.runeCount > kMaxNameLength) {
      errors[UserFormField.name] = '名前は $kMaxNameLength 文字以内で入力してください';
    }
  }

  if (email != null) {
    final value = normalizeEmail(email);
    if (value.isEmpty) {
      errors[UserFormField.email] = 'メールアドレスを入力してください';
    } else if (value.runeCount > kMaxEmailLength) {
      errors[UserFormField.email] =
          'メールアドレスは $kMaxEmailLength 文字以内で入力してください';
    } else if (!_emailPattern.hasMatch(value)) {
      errors[UserFormField.email] = 'メールアドレスの形式が正しくありません';
    }
  }

  if (password != null) {
    // 判定の順序は Go 側の validatePassword と揃える。欄ごとに 1 つの理由しか
    // 表示しないため、順序が違うと同じ入力に別のエラーが出る。文字種を長さより
    // 先に見るのは、日本語を数文字入力した利用者に「8 文字以上」ではなく
    // 「半角英数字と記号で」と伝えるためである。
    if (password.isEmpty) {
      errors[UserFormField.password] = 'パスワードを入力してください';
    } else if (!_passwordPattern.hasMatch(password)) {
      errors[UserFormField.password] =
          'パスワードは半角英数字と記号（スペースを除く）で入力してください';
    } else if (password.length < kMinPasswordLength ||
        password.length > kMaxPasswordLength) {
      errors[UserFormField.password] =
          'パスワードは $kMinPasswordLength 文字以上 $kMaxPasswordLength 文字以内で入力してください';
    }
  }

  if (passwordConfirmation != null) {
    if (passwordConfirmation.isEmpty) {
      errors[UserFormField.passwordConfirmation] = '確認用のパスワードを入力してください';
    } else if (passwordConfirmation != password) {
      errors[UserFormField.passwordConfirmation] = 'パスワードが一致しません';
    }
  }

  return errors;
}

/// 文字数（コードポイントの数）。
///
/// `String.length` は UTF-16 のコード単位数を返すため、サロゲートペア（絵文字
/// など）を 2 文字と数えてしまう。Go 側は `utf8.RuneCountInString` で数えるため、
/// こちらもコードポイントの数で揃える。
///
/// パスワードの長さだけは `length` のままでよい。文字種の判定を先に通しており、
/// ASCII の 1 バイト文字しか残らないためである。
extension on String {
  int get runeCount => runes.length;
}
