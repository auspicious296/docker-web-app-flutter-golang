import 'dart:math' as math;

/// コンテンツ幅の最小値。
///
/// 1,366×768 の旧世代ノート PC（実効幅 1,366px から左右の余白を引いた値）で、
/// ユーザー一覧の全列が横スクロールなしに収まる幅。ウインドウがこれより狭い
/// 場合は、テーブル内に横スクロールを出して対応する。
const double kMinContentWidth = 1334;

/// コンテンツ幅の最大値。
///
/// 画面がどれだけ広くてもこれ以上は広げない。最も多い 1,920px のディスプレイで
/// 左右に余白が残り、1 行の横幅が広がりすぎて行を追いにくくなるのを防ぐため。
const double kMaxContentWidth = 1600;

/// 画面の左右の余白。
const double kScreenPadding = 16;

/// 使えるコンテンツ幅を求める。
///
/// [available] は左右の余白を差し引いた後の幅。最大値で頭打ちにするだけで、
/// 最小値はここでは使わない（[kMinContentWidth] を下回る場合は、テーブル自身が
/// 横スクロールを出して対応するため）。
double contentWidthFor(double available) => math.min(available, kMaxContentWidth);
