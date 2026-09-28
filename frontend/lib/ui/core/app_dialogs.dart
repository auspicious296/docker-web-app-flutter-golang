import 'package:flutter/material.dart';

/// 確認ダイアログを表示し、「はい」が押されたかを返す。
///
/// 通信を伴う操作の直前に挟む。ダイアログの外側をタップしても閉じないのは、
/// 「はい」と「いいえ」のどちらを選んだのかを必ず明示させるため。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('いいえ'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('はい'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 結果を知らせるアラートダイアログを表示する。
///
/// タイトル・メッセージと「OK」ボタンだけの構成で、タイトルバーに閉じるボタンは
/// 置かない。閉じる手段を OK に一本化するため。
///
/// 文言の一部だけ体裁を変えたい場合は [showRichAlertDialog] を使う。こちらは
/// 文字列 1 つを断片 1 つに包んでそちらへ渡すだけの薄い窓口である。
Future<void> showAlertDialog(
  BuildContext context, {
  required String title,
  required String message,
}) => showRichAlertDialog(
  context,
  title: title,
  message: [TextSpan(text: message)],
);

/// 文言を断片ごとに組み立てられるアラートダイアログ。
///
/// `Text` に対する `Text.rich` と同じ関係で、[showAlertDialog] では表せない
/// 「一部だけ色を変える」といった体裁を扱える。**ダイアログの体裁（外側タップで
/// 閉じない・OK だけ）はこの関数が持ち**、[showAlertDialog] はここへ委譲する。
/// 体裁を変える必要がない呼び出しは、引き続き [showAlertDialog] を使う。
///
/// 色を指定しない断片は、指定した場合と同じく `AlertDialog` の既定の体裁に従う。
Future<void> showRichAlertDialog(
  BuildContext context, {
  required String title,
  required List<TextSpan> message,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text.rich(TextSpan(children: message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
