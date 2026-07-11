import 'package:flutter/material.dart';

import '../data/models/account.dart';
import '../data/models/category.dart';
import '../data/models/transaction.dart';
import 'amount_text.dart';
import 'category_avatar.dart';

/// Reusable list tile for a single transaction.
///
/// Shows: CategoryAvatar · description/type · category + account · amount.
/// Used by both the Transactions (historial) and Dashboard (recent) screens.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    this.category,
    this.account,
    this.onTap,
    this.dense = false,
  });

  final Transaction transaction;
  final Category? category;
  final Account? account;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = transaction;

    final subtitle = [
      if (category != null) category!.name else 'Sin categoría',
      if (account != null) account!.name,
    ].join('  ·  ');

    return ListTile(
      dense: dense,
      onTap: onTap,
      leading: CategoryAvatar(category: category, radius: dense ? 16 : 20),
      title: Text(
        tx.description ?? _typeLabel(tx.transactionType),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AmountText(
        amount: tx.amount,
        transactionType: tx.transactionType,
        showSign: true,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

const _txTypeLabels = {
  'expense': 'Gasto',
  'income': 'Ingreso',
  'transfer': 'Transferencia',
};

String _typeLabel(String type) => _txTypeLabels[type] ?? type;
