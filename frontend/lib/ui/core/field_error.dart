import 'package:flutter/material.dart';

/// 入力欄の下に出す検証エラー。
///
/// 背景は「削除」ボタンと同じ赤（`0xFFD32F2F`）。白い文字が読める範囲でもっとも
/// 柔らかい赤で、コントラスト比は約 5.0:1（WCAG AA が通常の文字に求める 4.5:1 を
/// 満たす）。これより薄い赤にすると白が読めなくなる。
///
/// 幅は内容に合わせて縮む。親が与える幅（登録画面では入力欄と同じ 460px）を
/// 超えるテキストだけが折り返し、その幅いっぱいになる。
class FieldError extends StatelessWidget {
  const FieldError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // 親の幅いっぱいに広がらないよう、左端に寄せた箱として置く
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD32F2F),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}
