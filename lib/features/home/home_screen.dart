import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/amount_formatter.dart';
import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../core/theme.dart';
import '../../data/models/account.dart';
import '../../data/models/budget.dart';
import '../../data/models/category.dart';
import '../../data/models/tracking_period.dart';
import '../../data/models/transaction.dart';
import '../../shared/insight_card.dart';
import '../../shared/period_hero_card.dart';
import '../../shared/sync_status_icon.dart';
import '../../shared/transaction_tile.dart';
import '../auth/auth_controller.dart';

// ---------------------------------------------------------------------------
// Provider for accounts (used inline in _AccountsCarousel)
// ---------------------------------------------------------------------------

final accountsForHomeProvider = FutureProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).list(),
);

// ---------------------------------------------------------------------------
// HomeScreen — Tab 0 (Inicio)
// Fuses old HomeScreen + DashboardScreen into one unified tab (mockup 12/13).
// ---------------------------------------------------------------------------

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final periodAsync = ref.watch(activeTrackingPeriodProvider);
    final txsAsync = ref.watch(localTransactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final accountsAsync = ref.watch(localAccountsProvider);
    final budgetsAsync = ref.watch(budgetsProvider);
    final currentView = ref.watch(dashboardViewProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(activeTrackingPeriodProvider);
          ref.invalidate(periodSummaryProvider);
          ref.invalidate(budgetsProvider);
          ref.read(syncControllerProvider.notifier).syncInBackground();
        },
        child: CustomScrollView(
          slivers: [
            // ---- Teal app bar ----
            _TealSliverAppBar(userName: user?.fullName ?? user?.email),

            // ---- Body content ----
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Period hero card — overlaps the appbar bottom
                  const SizedBox(height: BalviaTheme.spaceMd),
                  _PeriodHeroSection(
                    periodAsync: periodAsync,
                    txsAsync: txsAsync,
                    currentView: currentView,
                  ),
                  const SizedBox(height: BalviaTheme.spaceMd),

                  // View selector (Completa / Quincenal / Semanal)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BalviaTheme.spaceMd,
                    ),
                    child: _ViewSelector(currentView: currentView),
                  ),
                  const SizedBox(height: BalviaTheme.spaceMd),

                  // Insight card (spending pace from backend if available)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BalviaTheme.spaceMd,
                    ),
                    child: _InsightSection(periodAsync: periodAsync),
                  ),

                  // "Presupuestos en riesgo"
                  _AtRiskBudgetsSection(
                    budgetsAsync: budgetsAsync,
                    txsAsync: txsAsync,
                    categoriesAsync: categoriesAsync,
                  ),

                  // "Gasto por categoría" (horizontal bars)
                  _SpendByCategorySection(
                    txsAsync: txsAsync,
                    categoriesAsync: categoriesAsync,
                  ),

                  // "Últimas transacciones"
                  _RecentTransactionsSection(
                    txsAsync: txsAsync,
                    categoriesAsync: categoriesAsync,
                    accountsAsync: accountsAsync,
                  ),

                  // "Mis cuentas" carousel
                  _AccountsSection(accountsAsync: accountsAsync),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teal SliverAppBar
// ---------------------------------------------------------------------------

class _TealSliverAppBar extends ConsumerWidget {
  const _TealSliverAppBar({required this.userName});
  final String? userName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final greeting = _greeting(userName);
    return SliverAppBar(
      expandedHeight: 100,
      pinned: true,
      backgroundColor: BalviaTheme.seed,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF14B8A6), Color(0xFF0F9D8C)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                BalviaTheme.spaceMd,
                BalviaTheme.spaceSm,
                BalviaTheme.spaceMd,
                BalviaTheme.spaceSm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${_greetingPrefix()},\n',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          TextSpan(
                            text: greeting,
                            style: const TextStyle(
                              fontSize: 22,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Sync indicator
                  const SyncStatusIcon(compact: true),
                  const SizedBox(width: BalviaTheme.spaceSm),
                  // Avatar circle with initials
                  _AvatarCircle(name: userName),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _greetingPrefix() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String _greeting(String? name) {
    if (name == null || name.isEmpty) return 'Balvia';
    return name.split(' ').first;
  }
}

/// Returns the time-of-day greeting prefix (exported for tests).
String greetingPrefix(int hour) {
  if (hour < 12) return 'Buenos días';
  if (hour < 18) return 'Buenas tardes';
  return 'Buenas noches';
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final initials = name != null && name!.isNotEmpty
        ? name!.trim().split(' ').map((p) => p[0]).take(2).join().toUpperCase()
        : '?';

    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.white.withValues(alpha: 0.25),
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period hero section
// ---------------------------------------------------------------------------

class _PeriodHeroSection extends ConsumerWidget {
  const _PeriodHeroSection({
    required this.periodAsync,
    required this.txsAsync,
    required this.currentView,
  });

  final AsyncValue<TrackingPeriod> periodAsync;
  final AsyncValue<List<Transaction>> txsAsync;
  final String currentView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return periodAsync.when(
      loading: () => const _Skeleton(height: 220),
      error: (e, _) => _SectionError(message: apiErrorMessage(e)),
      data: (period) {
        // Compute totals from local transactions
        final txs = txsAsync.value ?? [];
        Decimal totalExpense = Decimal.zero;
        Decimal totalIncome = Decimal.zero;
        for (final tx in txs) {
          if (tx.transactionType == 'expense') {
            totalExpense += tx.amount;
          } else if (tx.transactionType == 'income') {
            totalIncome += tx.amount;
          }
        }
        final balance = totalIncome - totalExpense;

        return PeriodHeroCard(
          period: period,
          totalExpense: totalExpense,
          totalIncome: totalIncome,
          balance: balance,
          selectedView: currentView,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// View selector (Completa / Quincenal / Semanal) — pill-style
// ---------------------------------------------------------------------------

class _ViewSelector extends ConsumerWidget {
  const _ViewSelector({required this.currentView});
  final String currentView;

  static const _views = [
    ('full', 'Completa'),
    ('biweekly', 'Quincenal'),
    ('weekly', 'Semanal'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
      ),
      child: Row(
        children: _views.map((v) {
          final selected = currentView == v.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () =>
                  ref.read(dashboardViewProvider.notifier).setView(v.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
                ),
                child: Text(
                  v.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Insight section (spending_pace from backend if present, else placeholder)
// ---------------------------------------------------------------------------

class _InsightSection extends ConsumerWidget {
  const _InsightSection({required this.periodAsync});
  final AsyncValue<TrackingPeriod> periodAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Currently shows a static placeholder matching the mockup.
    // When GET /tracking-periods/:id/insights is consumed, replace with real data.
    return const InsightCard(
      title: 'Ritmo de gasto elevado',
      body:
          'Vas gastando más rápido de lo ideal. '
          'Monitorea tus gastos esta semana para mantenerte en presupuesto.',
      severity: InsightSeverity.warning,
      icon: Icons.trending_up,
    );
  }
}

// ---------------------------------------------------------------------------
// "Presupuestos en riesgo" (≥ 80%)
// ---------------------------------------------------------------------------

class _AtRiskBudgetsSection extends ConsumerWidget {
  const _AtRiskBudgetsSection({
    required this.budgetsAsync,
    required this.txsAsync,
    required this.categoriesAsync,
  });

  final AsyncValue<List<Budget>> budgetsAsync;
  final AsyncValue<List<Transaction>> txsAsync;
  final AsyncValue<List<Category>> categoriesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = budgetsAsync.value ?? [];
    final txs = txsAsync.value ?? [];
    final categories = categoriesAsync.value ?? [];

    if (budgets.isEmpty) return const SizedBox.shrink();

    // Build spent map
    final spentMap = <String?, Decimal>{};
    for (final tx in txs) {
      if (tx.transactionType != 'expense') continue;
      spentMap[tx.categoryId] =
          (spentMap[tx.categoryId] ?? Decimal.zero) + tx.amount;
    }

    // Filter to ≥ 80%
    final atRisk = budgets.where((b) {
      if (b.amount <= Decimal.zero) return false;
      final spent = spentMap[b.categoryId] ?? Decimal.zero;
      final pct = (spent / b.amount).toDouble() * 100;
      return pct >= 80;
    }).toList();

    if (atRisk.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            BalviaTheme.spaceMd,
            BalviaTheme.spaceMd,
            BalviaTheme.spaceMd,
            BalviaTheme.spaceSm,
          ),
          child: Row(
            children: [
              Text(
                'Presupuestos en riesgo',
                style: BalviaTheme.titleStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: Text(
                  'Ver todos',
                  style: TextStyle(
                    color: BalviaTheme.seed,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: BalviaTheme.spaceMd,
            ),
            itemCount: atRisk.length,
            separatorBuilder: (context, i) =>
                const SizedBox(width: BalviaTheme.spaceSm),
            itemBuilder: (_, i) {
              final b = atRisk[i];
              final cat = categories
                  .where((c) => c.id == b.categoryId)
                  .firstOrNull;
              final spent = spentMap[b.categoryId] ?? Decimal.zero;
              final pct = b.amount > Decimal.zero
                  ? (spent / b.amount).toDouble() * 100
                  : 0.0;
              final isExceeded = pct >= 100;
              return _AtRiskCard(
                categoryName: cat?.name ?? 'Global',
                spent: spent,
                budget: b.amount,
                pct: pct,
                isExceeded: isExceeded,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AtRiskCard extends StatelessWidget {
  const _AtRiskCard({
    required this.categoryName,
    required this.spent,
    required this.budget,
    required this.pct,
    required this.isExceeded,
  });

  final String categoryName;
  final Decimal spent;
  final Decimal budget;
  final double pct;
  final bool isExceeded;

  @override
  Widget build(BuildContext context) {
    final color = isExceeded ? BalviaTheme.expense : BalviaTheme.budgetWarning;
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 150,
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            categoryName,
            style: BalviaTheme.bodyStyle(
              color: cs.onSurface,
            ).copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${AmountFormatter.formatCOP(spent)} de ${AmountFormatter.formatCOP(budget)}',
            style: BalviaTheme.captionStyle(
              color: color,
            ).copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: cs.outlineVariant,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: BalviaTheme.captionStyle(
                  color: color,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Icon(
                isExceeded ? Icons.circle : Icons.warning_amber,
                size: 12,
                color: color,
              ),
              const SizedBox(width: 2),
              Text(
                isExceeded ? 'Excedido' : 'Alerta',
                style: BalviaTheme.captionStyle(color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Gasto por categoría" (horizontal bars)
// ---------------------------------------------------------------------------

class _SpendByCategorySection extends ConsumerWidget {
  const _SpendByCategorySection({
    required this.txsAsync,
    required this.categoriesAsync,
  });

  final AsyncValue<List<Transaction>> txsAsync;
  final AsyncValue<List<Category>> categoriesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = txsAsync.value ?? [];
    final categories = categoriesAsync.value ?? [];

    // Compute expense per category
    final spentMap = <String?, Decimal>{};
    Decimal totalExpense = Decimal.zero;
    for (final tx in txs) {
      if (tx.transactionType != 'expense') continue;
      totalExpense += tx.amount;
      spentMap[tx.categoryId] =
          (spentMap[tx.categoryId] ?? Decimal.zero) + tx.amount;
    }

    if (spentMap.isEmpty || totalExpense <= Decimal.zero) {
      return const SizedBox.shrink();
    }

    // Sort descending by amount
    final sorted = spentMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            BalviaTheme.spaceMd,
            BalviaTheme.spaceMd,
            BalviaTheme.spaceMd,
            BalviaTheme.spaceSm,
          ),
          child: Text(
            'Gasto por categoría',
            style: BalviaTheme.titleStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        ...top.map((entry) {
          final cat = categories.where((c) => c.id == entry.key).firstOrNull;
          final fraction = totalExpense > Decimal.zero
              ? (entry.value / totalExpense).toDouble()
              : 0.0;
          return _CategorySpendRow(
            categoryName: cat?.name ?? 'Sin categoría',
            categoryColor: _resolveColor(cat),
            amount: entry.value,
            fraction: fraction,
          );
        }),
        const SizedBox(height: BalviaTheme.spaceSm),
      ],
    );
  }

  Color _resolveColor(Category? cat) {
    if (cat?.color != null) {
      final hex = cat!.color!.replaceFirst('#', '');
      if (hex.length == 6) {
        final value = int.tryParse('FF$hex', radix: 16);
        if (value != null) return Color(value);
      }
    }
    return BalviaTheme.expense;
  }
}

class _CategorySpendRow extends StatelessWidget {
  const _CategorySpendRow({
    required this.categoryName,
    required this.categoryColor,
    required this.amount,
    required this.fraction,
  });

  final String categoryName;
  final Color categoryColor;
  final Decimal amount;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BalviaTheme.spaceMd,
        0,
        BalviaTheme.spaceMd,
        BalviaTheme.spaceSm,
      ),
      child: Row(
        children: [
          // Category dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: categoryColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: BalviaTheme.spaceSm),
          SizedBox(
            width: 90,
            child: Text(
              categoryName,
              style: BalviaTheme.bodyStyle(color: cs.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: BalviaTheme.spaceSm),
          // Progress bar
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: cs.outlineVariant,
                color: categoryColor,
              ),
            ),
          ),
          const SizedBox(width: BalviaTheme.spaceSm),
          SizedBox(
            width: 80,
            child: Text(
              AmountFormatter.formatCOP(amount),
              textAlign: TextAlign.right,
              style: BalviaTheme.bodyStyle(
                color: cs.onSurface,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Últimas transacciones"
// ---------------------------------------------------------------------------

class _RecentTransactionsSection extends ConsumerWidget {
  const _RecentTransactionsSection({
    required this.txsAsync,
    required this.categoriesAsync,
    required this.accountsAsync,
  });

  final AsyncValue<List<Transaction>> txsAsync;
  final AsyncValue<List<Category>> categoriesAsync;
  final AsyncValue<List<Account>> accountsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = (txsAsync.value ?? []).take(5).toList();
    final categories = categoriesAsync.value ?? [];
    final accounts = accountsAsync.value ?? [];

    if (txs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            BalviaTheme.spaceMd,
            BalviaTheme.spaceMd,
            BalviaTheme.spaceMd,
            0,
          ),
          child: Row(
            children: [
              Text(
                'Últimas transacciones',
                style: BalviaTheme.titleStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: Text(
                  'Ver todas',
                  style: TextStyle(
                    color: BalviaTheme.seed,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...txs.map((tx) {
          final cat = categories
              .where((c) => c.id == tx.categoryId)
              .firstOrNull;
          final account = accounts
              .where((a) => a.id == tx.accountId)
              .firstOrNull;
          return TransactionTile(
            transaction: tx,
            category: cat,
            account: account,
          );
        }),
        const SizedBox(height: BalviaTheme.spaceSm),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// "Mis cuentas" horizontal carousel
// ---------------------------------------------------------------------------

class _AccountsSection extends ConsumerWidget {
  const _AccountsSection({required this.accountsAsync});
  final AsyncValue<List<Account>> accountsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = accountsAsync.value ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            BalviaTheme.spaceMd,
            BalviaTheme.spaceMd,
            BalviaTheme.spaceMd,
            BalviaTheme.spaceSm,
          ),
          child: Row(
            children: [
              Text(
                'Mis cuentas',
                style: BalviaTheme.titleStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/accounts'),
                child: Text(
                  'Gestionar',
                  style: TextStyle(
                    color: BalviaTheme.seed,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BalviaTheme.spaceMd,
            ),
            child: Text(
              'Aún no tienes cuentas. Crea una desde Gestionar.',
              style: BalviaTheme.bodyStyle(color: BalviaTheme.inkMuted),
            ),
          )
        else
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: BalviaTheme.spaceMd,
              ),
              itemCount: accounts.length,
              separatorBuilder: (context, i) =>
                  const SizedBox(width: BalviaTheme.spaceSm),
              itemBuilder: (_, i) => _AccountCard(account: accounts[i]),
            ),
          ),
        const SizedBox(height: BalviaTheme.spaceMd),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNegative = account.currentBalance < Decimal.zero;

    return Container(
      width: 130,
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: cs.primaryContainer,
            child: Icon(
              _accountIcon(account.accountType),
              size: 18,
              color: cs.primary,
            ),
          ),
          const Spacer(),
          Text(
            account.name,
            style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            AmountFormatter.formatCOP(account.currentBalance),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isNegative ? BalviaTheme.expense : BalviaTheme.seed,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  IconData _accountIcon(String type) => switch (type) {
    'cash' => Icons.payments_outlined,
    'checking' => Icons.account_balance_outlined,
    'savings' => Icons.savings_outlined,
    'credit_card' => Icons.credit_card_outlined,
    'investment' => Icons.trending_up_outlined,
    _ => Icons.account_balance_wallet_outlined,
  };
}

// ---------------------------------------------------------------------------
// Add account dialog (kept for compatibility with /accounts route)
// ---------------------------------------------------------------------------

void showAddAccountDialog(BuildContext context, WidgetRef ref) {
  showDialog<void>(
    context: context,
    builder: (_) => const _AddAccountDialog(),
  ).then((_) => ref.invalidate(activeTrackingPeriodProvider));
}

class _AddAccountDialog extends ConsumerStatefulWidget {
  const _AddAccountDialog();
  @override
  ConsumerState<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<_AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _balance = TextEditingController(text: '0');
  String _type = 'cash';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .create(
            name: _name.text.trim(),
            accountType: _type,
            initialBalance: _balance.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
        setState(() => _saving = false);
      }
    }
  }

  static const _accountTypes = {
    'cash': 'Efectivo',
    'checking': 'Cuenta corriente',
    'savings': 'Ahorros',
    'credit_card': 'Tarjeta de crédito',
    'investment': 'Inversión',
    'other': 'Otra',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva cuenta'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: _accountTypes.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? 'cash'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _balance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Saldo inicial',
                helperText: 'El saldo solo cambia con transacciones después.',
              ),
              validator: (v) => (v == null || double.tryParse(v) == null)
                  ? 'Número inválido'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BalviaTheme.spaceMd),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(BalviaTheme.radiusLg),
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BalviaTheme.spaceMd),
      child: Card(
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(BalviaTheme.spaceMd),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: cs.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
