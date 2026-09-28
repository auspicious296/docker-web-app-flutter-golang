import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/content_width.dart';

/// ホーム画面（アプリの入口）。
///
/// 各機能への入口を並べる一覧。状態を持たないため ViewModel は置かない。
/// 開発が進むたびに、この一覧へ行を追加していく
/// （ユーザー管理、ログインなど）。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('myapp')),
      // 他の画面と同じコンテンツ幅に収めて中央へ置き、余った幅は左右に均等に残す
      body: Padding(
        padding: const EdgeInsets.all(kScreenPadding),
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidthFor(constraints.maxWidth),
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('API 疎通テスト'),
                    subtitle: const Text('/api/health を呼び出して結果を表示します'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/health'),
                  ),
                  ListTile(
                    title: const Text('ユーザー管理'),
                    subtitle: const Text('ユーザーの一覧・登録・編集・削除を行います'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/users'),
                  ),
                  ListTile(
                    title: const Text('ユーザーログイン'),
                    subtitle: const Text('ログインしてマイページを表示します'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
