import 'package:flutter/material.dart';

/// 通信中に画面全体を覆うローダー。
///
/// `Stack` の最前面に `Positioned.fill` で重ねて使う。裏が透けて見える濃さに
/// しているのは、どの画面で処理が走っているかを伝えるため。`showDialog` ではなく
/// 状態から描くことで、View に状態を持たせない方針を保っている。
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const AbsorbPointer(
      child: ColoredBox(
        // 黒の 40%（0x66 = 255 の 40%）
        color: Color(0x66000000),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}
