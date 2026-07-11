// Data models for the sync protocol defined in docs/API_CONTRACT.md §Sync.
//
// These are plain Dart classes (no Drift) used exclusively by the sync engine
// to decode server responses and build push payloads. They are NOT stored as
// separate entities — the engine maps them directly into Drift companion objects.

/// Response from GET /sync/pull.
class PullResponse {
  const PullResponse({
    required this.serverTime,
    required this.hasMore,
    required this.transactions,
    required this.accounts,
    required this.categories,
    required this.budgets,
    required this.savingsGoals,
    required this.goalContributions,
    required this.recurringTransactions,
    required this.trackingPeriods,
  });

  /// RFC3339. Saved as the next `since` cursor when has_more == false.
  final String serverTime;

  /// True when at least one collection was truncated at page_size.
  final bool hasMore;

  // Raw JSON rows — each is a Map<String, dynamic> mirroring the server struct.
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> budgets;
  final List<Map<String, dynamic>> savingsGoals;
  final List<Map<String, dynamic>> goalContributions;
  final List<Map<String, dynamic>> recurringTransactions;
  final List<Map<String, dynamic>> trackingPeriods;

  factory PullResponse.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> extractList(String key) {
      final raw = json[key];
      if (raw == null) return const [];
      return (raw as List).map((e) => e as Map<String, dynamic>).toList();
    }

    return PullResponse(
      serverTime: json['server_time'] as String,
      hasMore: json['has_more'] as bool,
      transactions: extractList('transactions'),
      accounts: extractList('accounts'),
      categories: extractList('categories'),
      budgets: extractList('budgets'),
      savingsGoals: extractList('savings_goals'),
      goalContributions: extractList('goal_contributions'),
      recurringTransactions: extractList('recurring_transactions'),
      trackingPeriods: extractList('tracking_periods'),
    );
  }

  /// Returns the oldest updated_at among the last rows of truncated collections.
  /// Used to advance `since` when has_more == true per the contract protocol.
  String? oldestLastUpdatedAt() {
    final candidates = <String>[];

    void addLast(List<Map<String, dynamic>> rows) {
      if (rows.isNotEmpty) {
        final val = rows.last['updated_at'] as String?;
        if (val != null) candidates.add(val);
      }
    }

    addLast(transactions);
    addLast(accounts);
    addLast(categories);
    addLast(budgets);
    addLast(savingsGoals);
    addLast(goalContributions);
    addLast(recurringTransactions);
    addLast(trackingPeriods);

    if (candidates.isEmpty) return null;
    candidates.sort();
    return candidates.first; // oldest
  }
}

// ---------------------------------------------------------------------------
// Push request / response
// ---------------------------------------------------------------------------

/// One item in POST /sync/push `items` array.
class PushItem {
  const PushItem({
    required this.clientRef,
    required this.entityType,
    required this.operation,
    this.entityId,
    this.clientUpdatedAt,
    this.transactionPayload,
  });

  final String clientRef;
  final String entityType; // "transaction" in v1
  final String operation; // "create" | "update" | "delete"
  final String? entityId;
  final String? clientUpdatedAt; // for update conflict detection
  final Map<String, dynamic>? transactionPayload;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'client_ref': clientRef,
      'entity_type': entityType,
      'operation': operation,
    };
    if (entityId != null) m['entity_id'] = entityId;
    if (clientUpdatedAt != null) m['client_updated_at'] = clientUpdatedAt;
    if (transactionPayload != null) {
      m['transaction_payload'] = transactionPayload;
    }
    return m;
  }
}

/// The push result for a single item from the server.
class PushItemResult {
  const PushItemResult({
    required this.clientRef,
    required this.status,
    this.serverEntity,
    this.error,
  });

  final String clientRef;

  /// applied | skipped | conflict | rejected
  final String status;

  /// The full server row; present for applied/skipped/conflict.
  final Map<String, dynamic>? serverEntity;

  /// Human-readable error; present for rejected.
  final String? error;

  factory PushItemResult.fromJson(Map<String, dynamic> json) => PushItemResult(
    clientRef: json['client_ref'] as String,
    status: json['status'] as String,
    serverEntity: json['server_entity'] as Map<String, dynamic>?,
    error: json['error'] as String?,
  );
}

/// Full response from POST /sync/push.
class PushResponse {
  const PushResponse({required this.results});

  final List<PushItemResult> results;

  factory PushResponse.fromJson(Map<String, dynamic> json) => PushResponse(
    results: (json['results'] as List)
        .map((e) => PushItemResult.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
