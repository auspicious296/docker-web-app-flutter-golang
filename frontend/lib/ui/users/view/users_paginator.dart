import 'package:flutter/material.dart';

import '../view_model/users_view_model.dart';

/// テーブルの直下に置くページ送り。
///
/// 1 ページの行数は 20 で固定のため、行数を変える操作は置かない。総ページ数は
/// API が返さないので、総件数と 1 ページの行数から算出している。
class UsersPaginator extends StatelessWidget {
  const UsersPaginator({
    super.key,
    required this.state,
    required this.onPageChanged,
  });

  final UsersState state;
  final void Function(int page) onPageChanged;

  @override
  Widget build(BuildContext context) {
    final hasRows = state.total > 0;
    final canGoBack = hasRows && !state.isFirstPage;
    final canGoForward = hasRows && !state.isLastPage;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          hasRows
              ? '${state.total} 件中 ${state.firstRowNumber}〜${state.lastRowNumber} 件'
              : '0 件',
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: '先頭のページ',
          icon: const Icon(Icons.first_page),
          onPressed: canGoBack ? () => onPageChanged(1) : null,
        ),
        IconButton(
          tooltip: '前のページ',
          icon: const Icon(Icons.chevron_left),
          onPressed: canGoBack ? () => onPageChanged(state.page - 1) : null,
        ),
        IconButton(
          tooltip: '次のページ',
          icon: const Icon(Icons.chevron_right),
          onPressed: canGoForward ? () => onPageChanged(state.page + 1) : null,
        ),
        IconButton(
          tooltip: '最後のページ',
          icon: const Icon(Icons.last_page),
          onPressed: canGoForward
              ? () => onPageChanged(state.totalPages)
              : null,
        ),
      ],
    );
  }
}
