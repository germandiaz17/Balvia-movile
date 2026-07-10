import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'token_storage.dart';
import '../data/models/category.dart';
import '../data/models/period_summary.dart';
import '../data/models/tracking_period.dart';
import '../data/models/transaction.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/tracking_period_repository.dart';
import '../data/repositories/transaction_repository.dart';

/// Bumped by the API client when a session expires (refresh failed). The auth
/// controller listens to this to flip to logged-out — keeps infra decoupled
/// from the controller (no circular dependency).
class SessionExpiredNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final sessionExpiredProvider = NotifierProvider<SessionExpiredNotifier, int>(
  SessionExpiredNotifier.new,
);

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(tokenStorageProvider),
    () async => ref.read(sessionExpiredProvider.notifier).bump(),
  );
});

final dioProvider = Provider<Dio>((ref) => ref.watch(apiClientProvider).dio);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      AuthRepository(ref.watch(dioProvider), ref.watch(tokenStorageProvider)),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(dioProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(dioProvider)),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(dioProvider)),
);

final trackingPeriodRepositoryProvider = Provider<TrackingPeriodRepository>(
  (ref) => TrackingPeriodRepository(ref.watch(dioProvider)),
);

/// Categories are cached for the session (not autoDispose).
/// The quick-capture modal reads from this provider — it stays warm after
/// the first fetch so subsequent opens are instant.
final categoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).list(),
);

/// The currently active tracking period. autoDispose so it re-fetches when
/// the dashboard is opened/revisited.
final activeTrackingPeriodProvider = FutureProvider.autoDispose<TrackingPeriod>(
  (ref) => ref.watch(trackingPeriodRepositoryProvider).getActive(),
);

/// Holds the selected view for the dashboard summary selector.
/// Possible values: "full" | "biweekly" | "weekly".
class DashboardViewNotifier extends Notifier<String> {
  @override
  String build() => 'full';

  void setView(String view) => state = view;
}

final dashboardViewProvider = NotifierProvider<DashboardViewNotifier, String>(
  DashboardViewNotifier.new,
);

/// Summary for the active period + selected view. Depends on both the active
/// period and the chosen view, so it auto-re-fetches when either changes.
/// Awaiting `.future` keeps this provider in loading state (not error) while
/// the active period itself is still loading.
final periodSummaryProvider = FutureProvider.autoDispose<PeriodSummary>((
  ref,
) async {
  final view = ref.watch(dashboardViewProvider);
  final repo = ref.watch(trackingPeriodRepositoryProvider);
  final period = await ref.watch(activeTrackingPeriodProvider.future);
  return repo.getSummary(period.id, view: view);
});

/// Recent transactions for the active period (last ~10, sorted desc by date).
/// The repository already defaults to the active period when no ID is given.
final recentTransactionsProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) async {
      final repo = ref.watch(transactionRepositoryProvider);
      final all = await repo.list();
      // Sort descending by date (most recent first) and take up to 10.
      final sorted = List<Transaction>.from(all)
        ..sort((a, b) {
          final dateCmp = b.transactionDate.compareTo(a.transactionDate);
          if (dateCmp != 0) return dateCmp;
          return b.createdAt.compareTo(a.createdAt);
        });
      return sorted.take(10).toList();
    });

/// All transactions for the active tracking period, sorted newest-first.
/// Used by the Movimientos screen. autoDispose so it refreshes on tab re-enter.
final allTransactionsProvider =
    FutureProvider.autoDispose<List<Transaction>>((ref) async {
      final repo = ref.watch(transactionRepositoryProvider);
      final all = await repo.list();
      return List<Transaction>.from(all)
        ..sort((a, b) {
          final dateCmp = b.transactionDate.compareTo(a.transactionDate);
          if (dateCmp != 0) return dateCmp;
          return b.createdAt.compareTo(a.createdAt);
        });
    });
