import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'routing/router.dart';

void main() {
  // Flutter Web の URL からハッシュ（#）を取り除く。
  // 呼ばないと https://myapp.local/#/health のような URL になる。
  // nginx 側は存在しないパスを index.html へ返す設定（try_files）が
  // 済んでいるため、直接 URL を開いても表示できる。
  usePathUrlStrategy();

  // ProviderScope は Riverpod の provider を保持する入れ物。
  // アプリ全体を包む必要がある。
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'myapp',
      theme: ThemeData(
        // アプリの基調色。ユーザー一覧のテーブルヘッダーに使うコバルト系の青に
        // 合わせている（Flutter のプロジェクト作成時の既定値である deepPurple は、
        // 意図して選んだ色ではないため置き換えた）。
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0047AB)),
      ),
      // routerConfig: router ではなく部品ごとに渡す。ブラウザの履歴の記録だけを
      // 差し替えるため（router.dart の routeInformationProvider を参照）。
      routeInformationProvider: routeInformationProvider,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
      backButtonDispatcher: router.backButtonDispatcher,
    );
  }
}
