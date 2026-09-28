import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/domain/models/user_form_field.dart';
import 'package:frontend/domain/models/user_validation.dart';

/// 入力検証の組み合わせを確かめる。
///
/// ここで確かめるのは Dart 側の判定だけで、Go 側の `service` にも同じルールが
/// ある（意図した二重化。ADR 0008）。両者がずれた場合はサーバーが弾き、その
/// 内訳が同じ入力欄の直下に出るため、画面が黙って通すことはない。
void main() {
  const validName = '山田 太郎';
  const validEmail = 'yamada@example.com';
  const validPassword = 'password123';

  /// 正しい値を既定とし、指定した項目だけを差し替えて検証する。
  Map<UserFormField, String> validate({
    String? name,
    String? email,
    String? password,
    String? passwordConfirmation,
  }) => validateUserForm(
    name: name ?? validName,
    email: email ?? validEmail,
    password: password ?? validPassword,
    passwordConfirmation: passwordConfirmation ?? password ?? validPassword,
  );

  group('ユーザー名', () {
    test('正しい値はエラーにならない', () {
      expect(validate(), isEmpty);
    });

    test('空は未入力', () {
      expect(validate(name: '')[UserFormField.name], '名前を入力してください');
    });

    test('半角スペースのみは未入力', () {
      expect(validate(name: '   ')[UserFormField.name], '名前を入力してください');
    });

    test('全角スペースのみは未入力（半角に置換してから除去するため）', () {
      expect(validate(name: '　　')[UserFormField.name], '名前を入力してください');
    });

    test('前後の空白は除去してから数える', () {
      expect(validate(name: '  山田 太郎  '), isEmpty);
    });

    test('255 文字は通る', () {
      expect(validate(name: 'あ' * 255), isEmpty);
    });

    test('256 文字は長すぎ', () {
      expect(
        validate(name: 'あ' * 256)[UserFormField.name],
        '名前は 255 文字以内で入力してください',
      );
    });

    test('サロゲートペアは 1 文字として数える', () {
      // String.length では 2 と数えるため、255 個の絵文字が 510 文字になる
      expect(validate(name: '😀' * 255), isEmpty);
    });
  });

  group('メールアドレス', () {
    test('空は未入力', () {
      expect(
        validate(email: '')[UserFormField.email],
        'メールアドレスを入力してください',
      );
    });

    test('前後の空白は除去する', () {
      expect(validate(email: '  yamada@example.com  '), isEmpty);
    });

    test('@ がなければ形式エラー', () {
      expect(
        validate(email: 'not-an-email')[UserFormField.email],
        'メールアドレスの形式が正しくありません',
      );
    });

    test('ドメインにドットがなければ形式エラー', () {
      expect(
        validate(email: 'a@b')[UserFormField.email],
        'メールアドレスの形式が正しくありません',
      );
    });

    test('表示名付きは形式エラー', () {
      expect(
        validate(email: '山田 <a@example.com>')[UserFormField.email],
        'メールアドレスの形式が正しくありません',
      );
    });

    test('大文字のままでもエラーにならない（小文字化は Go 側が行う）', () {
      expect(validate(email: 'Yamada@Example.COM'), isEmpty);
    });

    test('256 文字は長すぎ', () {
      final local = 'a' * (256 - '@example.com'.length);
      expect(
        validate(email: '$local@example.com')[UserFormField.email],
        'メールアドレスは 255 文字以内で入力してください',
      );
    });
  });

  group('パスワード', () {
    const tooShortOrLong = 'パスワードは 8 文字以上 72 文字以内で入力してください';
    const invalidFormat = 'パスワードは半角英数字と記号（スペースを除く）で入力してください';

    test('空は未入力', () {
      expect(
        validate(password: '')[UserFormField.password],
        'パスワードを入力してください',
      );
    });

    test('7 文字は短すぎ', () {
      expect(validate(password: '1234567')[UserFormField.password], tooShortOrLong);
    });

    test('8 文字は通る', () {
      expect(validate(password: '12345678'), isEmpty);
    });

    test('記号だけでも通る', () {
      expect(validate(password: r'!"#$%&' "'("), isEmpty);
    });

    test('72 文字は通る', () {
      expect(validate(password: 'a' * 72), isEmpty);
    });

    test('73 文字は長すぎ', () {
      expect(validate(password: 'a' * 73)[UserFormField.password], tooShortOrLong);
    });

    test('日本語を含むと文字種エラー', () {
      expect(validate(password: 'パスワード1234')[UserFormField.password], invalidFormat);
    });

    test('スペースを含むと文字種エラー', () {
      expect(validate(password: 'pass word123')[UserFormField.password], invalidFormat);
    });

    test('全角の記号を含むと文字種エラー', () {
      expect(validate(password: 'password１２３')[UserFormField.password], invalidFormat);
    });

    test('文字種は長さより先に判定する', () {
      // 日本語 3 文字は「短すぎ」でもあるが、文字種のエラーを出す
      expect(validate(password: 'あいう')[UserFormField.password], invalidFormat);
    });
  });

  group('確認用パスワード', () {
    test('空は未入力', () {
      expect(
        validate(passwordConfirmation: '')[UserFormField.passwordConfirmation],
        '確認用のパスワードを入力してください',
      );
    });

    test('一致しなければエラー', () {
      expect(
        validate(
          password: 'password123',
          passwordConfirmation: 'password124',
        )[UserFormField.passwordConfirmation],
        'パスワードが一致しません',
      );
    });

    test('渡さなければ判定しない（確認用の欄がない画面のため）', () {
      expect(validateUserForm(password: validPassword), isEmpty);
    });
  });

  group('複数の項目', () {
    test('不正な項目をすべて返す', () {
      final errors = validateUserForm(
        name: '',
        email: 'a@b',
        password: '123',
        passwordConfirmation: '',
      );
      expect(errors.keys, {
        UserFormField.name,
        UserFormField.email,
        UserFormField.password,
        UserFormField.passwordConfirmation,
      });
    });

    test('1 つの項目には 1 つの理由しか入らない', () {
      // 空のパスワードは「未入力」であり、文字種や長さのエラーにはしない
      final errors = validateUserForm(password: '');
      expect(errors[UserFormField.password], 'パスワードを入力してください');
    });
  });
}
