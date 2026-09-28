import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'content_width.dart';

/// 「戻る」ボタン付きのタイトルバー。
///
/// ボタンは画面の左端ではなく、**コンテンツ幅の左端**に揃える。`AppBar` の
/// `leading` は画面の左端に固定されて位置を動かせないため、`titleSpacing: 0` で
/// タイトル領域を全幅まで広げ、その中で自前に配置している。
///
/// 戻り先の既定はホーム画面。ホーム画面の一覧から開く画面（疎通確認・ユーザー
/// 管理）は `context.go` で遷移しており Navigator のスタックに積まれていないため、
/// `pop` ではなくパスを指定して戻る。
///
/// ユーザー登録画面のように `context.push` で積んだ画面は、[onBack] に
/// `context.pop` を渡して戻り方だけを差し替える。ボタンの位置合わせ（画面の
/// 左端ではなくコンテンツ幅の左端に揃える仕組み）は共有したまま使える。
///
/// [trailing] を渡すと、**コンテンツ幅の右端**に置く（「戻る」ボタンを左端に
/// 揃えるのと同じ仕組み）。マイページなどの「ユーザー名」ボタンに使う。
class BackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BackAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String title;

  /// 「戻る」を押したときの処理。`null` ならホーム画面へ `go` する。
  final VoidCallback? onBack;

  /// コンテンツ幅の右端に置くウィジェット。`null` なら何も置かない。
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // 既定の戻る矢印を出さない（位置を動かせないため自前で置く）
      automaticallyImplyLeading: false,
      // タイトル領域をバーの全幅まで広げ、その中で位置を決める
      titleSpacing: 0,
      title: LayoutBuilder(
        builder: (context, constraints) => Align(
          child: SizedBox(
            width: contentWidthFor(
              constraints.maxWidth - kScreenPadding * 2,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 箱の中央。箱自体が中央にあるため、見た目はバーの中央と一致する
                Text(title),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onBack ?? () => context.go('/'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('戻る'),
                  ),
                ),
                if (trailing != null)
                  Align(alignment: Alignment.centerRight, child: trailing),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
