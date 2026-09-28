import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/app_dialogs.dart';
import '../view_model/session_view_model.dart';

/// [confirmAndLogout] の結果。画面の移り先は呼び出し側が決める。
enum LogoutFlowResult {
  /// ログアウトしなかった（「いいえ」、またはログアウトに失敗した）。元の画面に留まる。
  stayed,

  /// ログアウトできた。
  loggedOut,

  /// ログイン状態が切れていた。ダイアログは表示済みで、ログイン画面へ移る。
  sessionExpired,
}

/// ログアウトの確認ダイアログを出し、「はい」ならログアウトする（ADR 0015）。
///
/// メニューの「ログアウト」と、マイページの「戻る」・ブラウザの戻る（ルートの
/// `onExit`）の両方から呼ぶ。確認と失敗時のダイアログはここで出し、ログアウト
/// できた後の移り先（ログイン画面・ホーム画面）は呼び出し側が決める。
Future<LogoutFlowResult> confirmAndLogout(BuildContext context) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'ログアウトします',
    message: 'ログアウトしてよろしいですか？',
  );
  if (!confirmed || !context.mounted) return LogoutFlowResult.stayed;

  final outcome = await ProviderScope.containerOf(
    context,
    listen: false,
  ).read(sessionViewModelProvider.notifier).logout();
  if (!context.mounted) return LogoutFlowResult.stayed;

  switch (outcome) {
    case LogoutSuccess():
      return LogoutFlowResult.loggedOut;

    case LogoutUnauthenticated():
      await showSessionExpiredDialog(context);
      return LogoutFlowResult.sessionExpired;

    case LogoutFailed(:final message):
      await showAlertDialog(context, title: 'ログアウトできませんでした', message: message);
      return LogoutFlowResult.stayed;
  }
}

/// 画面の操作で、ログイン状態が切れていた（401）ことを知らせる（ADR 0015）。
///
/// 「OK」の後、呼び出し側がログイン画面へ移す。
Future<void> showSessionExpiredDialog(BuildContext context) => showAlertDialog(
  context,
  title: 'ログイン状態が切れました',
  message: 'ログイン状態が切れました。もう一度ログインしてください。',
);
