import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../domain/enums/transaction_type.dart';
import '../../domain/models/transaction_context.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Immutable view-model for the paginated transaction list.
class TransactionListState {
  const TransactionListState({
    this.items = const [],
    this.total = 0,
    this.hasMore = false,
    this.initialLoading = true,
    this.loadingMore = false,
    this.search = '',
    this.type,
  });

  final List<TransactionContext> items;

  /// Total rows matching the current filters (from the count stream).
  final int total;

  final bool hasMore;
  final bool initialLoading;
  final bool loadingMore;
  final String search;
  final TransactionType? type;

  TransactionListState copyWith({
    List<TransactionContext>? items,
    int? total,
    bool? hasMore,
    bool? initialLoading,
    bool? loadingMore,
    String? search,
    TransactionType? type,
  }) => TransactionListState(
    items: items ?? this.items,
    total: total ?? this.total,
    hasMore: hasMore ?? this.hasMore,
    initialLoading: initialLoading ?? this.initialLoading,
    loadingMore: loadingMore ?? this.loadingMore,
    search: search ?? this.search,
    type: type ?? this.type,
  );
}

/// Loads the transaction list in fixed-size windows with DB-level search and
/// type filters, so very large histories stay responsive.
class TransactionListController extends StateNotifier<TransactionListState> {
  TransactionListController(this._repository) : super(const TransactionListState()) {
    _subscribeToCount();
    _loadFirstPage();
  }

  /// Rows fetched per page.
  static const int pageSize = 100;

  final TransactionRepository _repository;
  StreamSubscription<int>? _countSubscription;

  void _subscribeToCount() {
    _countSubscription?.cancel();
    _countSubscription = _repository
        .watchContextCount(search: state.search, type: state.type)
        .listen((total) {
      // Any write elsewhere (add/edit/delete) changes the total; reload the
      // first page so the visible window stays fresh.
      if (total != state.total) {
        state = state.copyWith(total: total);
        _loadFirstPage();
      }
    });
  }

  Future<void> _loadFirstPage() async {
    state = state.copyWith(initialLoading: true);
    final page = await _repository.contextPage(
      limit: pageSize,
      offset: 0,
      search: state.search,
      type: state.type,
    );
    if (!mounted) return;
    state = state.copyWith(
      items: page,
      initialLoading: false,
      hasMore: page.length == pageSize,
    );
  }

  Future<void> loadMore() async {
    if (state.initialLoading || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    final page = await _repository.contextPage(
      limit: pageSize,
      offset: state.items.length,
      search: state.search,
      type: state.type,
    );
    if (!mounted) return;
    state = state.copyWith(
      items: [...state.items, ...page],
      loadingMore: false,
      hasMore: page.length == pageSize,
    );
  }

  /// Applies new search / type filters, reloading from the first page.
  Future<void> setFilters({String? search, TransactionType? type}) async {
    if (search == state.search && type == state.type) return;
    state = state.copyWith(search: search ?? '', type: type);
    _subscribeToCount();
    await _loadFirstPage();
  }

  @override
  void dispose() {
    _countSubscription?.cancel();
    super.dispose();
  }
}

/// The paginated transaction list controller (wired to the repository).
final transactionListControllerProvider =
    StateNotifierProvider<TransactionListController, TransactionListState>((ref) {
      return TransactionListController(
        ref.watch(transactionRepositoryProvider),
      );
    });
