import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../data/models/transaction.dart';

/// State for the quick-capture modal.
class QuickCaptureState {
  const QuickCaptureState({
    this.rawDigits = '',
    this.transactionType = 'expense',
    this.selectedCategoryId,
    this.selectedAccountId,
    this.description = '',
    this.isLoading = false,
    this.isSuggesting = false,
    this.error,
    this.savedTransaction,
    this.suggestedCategoryId,
    this.suggestedConfidence,
  });

  /// Digit string the user has typed on the numeric keypad — no separators.
  final String rawDigits;

  /// "expense" | "income"
  final String transactionType;
  final String? selectedCategoryId;
  final String? selectedAccountId;
  final String description;
  final bool isLoading;

  /// True while an AI category suggestion is in flight.
  final bool isSuggesting;
  final String? error;

  /// Set when a transaction has been successfully saved.
  final Transaction? savedTransaction;

  /// The category id the AI last suggested for this capture (null if none was
  /// ever produced). Persisted onto the saved transaction to measure accuracy.
  final String? suggestedCategoryId;

  /// The confidence (0..1) of the AI suggestion. Transient double from the API;
  /// converted to Decimal when persisted.
  final double? suggestedConfidence;

  QuickCaptureState copyWith({
    String? rawDigits,
    String? transactionType,
    Object? selectedCategoryId = _sentinel,
    String? selectedAccountId,
    String? description,
    bool? isLoading,
    bool? isSuggesting,
    Object? error = _sentinel,
    Object? savedTransaction = _sentinel,
    Object? suggestedCategoryId = _sentinel,
    Object? suggestedConfidence = _sentinel,
  }) {
    return QuickCaptureState(
      rawDigits: rawDigits ?? this.rawDigits,
      transactionType: transactionType ?? this.transactionType,
      selectedCategoryId: selectedCategoryId == _sentinel
          ? this.selectedCategoryId
          : selectedCategoryId as String?,
      selectedAccountId: selectedAccountId ?? this.selectedAccountId,
      description: description ?? this.description,
      isLoading: isLoading ?? this.isLoading,
      isSuggesting: isSuggesting ?? this.isSuggesting,
      error: error == _sentinel ? this.error : error as String?,
      savedTransaction: savedTransaction == _sentinel
          ? this.savedTransaction
          : savedTransaction as Transaction?,
      suggestedCategoryId: suggestedCategoryId == _sentinel
          ? this.suggestedCategoryId
          : suggestedCategoryId as String?,
      suggestedConfidence: suggestedConfidence == _sentinel
          ? this.suggestedConfidence
          : suggestedConfidence as double?,
    );
  }
}

// Sentinel value for nullable fields in copyWith.
const Object _sentinel = Object();

/// Controller for the quick-capture modal. Lives only while the modal is open
/// (autoDispose). Uses Riverpod 3.x pattern: `Notifier` +
/// `NotifierProvider.autoDispose(...)`.
class QuickCaptureController extends Notifier<QuickCaptureState> {
  @override
  QuickCaptureState build() => const QuickCaptureState();

  /// Initialize with the first available account pre-selected.
  void initWithAccount(String? accountId) {
    if (state.selectedAccountId == null && accountId != null) {
      state = state.copyWith(selectedAccountId: accountId);
    }
  }

  /// Appends a digit [0–9] to the amount string (max 10 digits ≈ 9 999 999 999).
  void appendDigit(String digit) {
    if (state.rawDigits.length >= 10) return;
    final current = state.rawDigits;
    // Prevent leading zeros.
    final next = (current == '0') ? digit : current + digit;
    state = state.copyWith(rawDigits: next, error: null);
  }

  /// Appends three zeros (",000" key — design system §4).
  /// Multiplies the current amount by 1000 in effect (adds "000" suffix).
  /// Capped at the same 10-digit maximum.
  void appendThousands() {
    final current = state.rawDigits;
    if (current.isEmpty || current == '0') return;
    const suffix = '000';
    final next = current + suffix;
    if (next.length > 10) return;
    state = state.copyWith(rawDigits: next, error: null);
  }

  /// Removes the last digit.
  void backspace() {
    final d = state.rawDigits;
    if (d.isEmpty) return;
    state = state.copyWith(
      rawDigits: d.substring(0, d.length - 1),
      error: null,
    );
  }

  void clearAmount() {
    state = state.copyWith(rawDigits: '', error: null);
  }

  void setTransactionType(String type) {
    // When switching type, clear category (expense ↔ income categories differ).
    state = state.copyWith(
      transactionType: type,
      selectedCategoryId: null,
      error: null,
    );
  }

  void selectCategory(String? categoryId) {
    state = state.copyWith(selectedCategoryId: categoryId, error: null);
  }

  void selectAccount(String accountId) {
    state = state.copyWith(selectedAccountId: accountId, error: null);
  }

  void setDescription(String desc) {
    state = state.copyWith(description: desc);
  }

  /// Asks the AI to suggest a category for the current description.
  ///
  /// Best-effort and explicit-tap only (the user pays per call). Swallows ALL
  /// errors — offline, 422 (AI not configured), 502 (bad key), 503 (disabled)
  /// — so it never surfaces an error or blocks the save flow. The suggestion is
  /// applied only when the returned category id exists among the user's
  /// categories for the current transaction type.
  Future<void> suggestCategory() async {
    final description = state.description.trim();
    if (description.isEmpty) return;
    if (state.isSuggesting) return;

    state = state.copyWith(isSuggesting: true);
    try {
      final suggestion = await ref
          .read(aiRepositoryProvider)
          .categorize(
            description: description,
            amount: state.rawDigits.isEmpty ? null : state.rawDigits,
            transactionType: state.transactionType,
          );
      final categoryId = suggestion.categoryId;
      if (categoryId != null) {
        final categories = await ref.read(categoriesProvider.future);
        final matches = categories.any(
          (c) => c.id == categoryId && c.categoryType == state.transactionType,
        );
        if (matches) {
          // Record the suggestion so save() can compare suggested-vs-chosen
          // and persist the accuracy metadata onto the transaction.
          state = state.copyWith(
            selectedCategoryId: categoryId,
            suggestedCategoryId: categoryId,
            suggestedConfidence: suggestion.confidence,
          );
        }
      }
    } catch (_) {
      // Best-effort: swallow everything.
    } finally {
      state = state.copyWith(isSuggesting: false);
    }
  }

  /// Validates and saves the transaction via the API.
  Future<void> save() async {
    final s = state;

    // Validate amount.
    final rawDigits = s.rawDigits;
    if (rawDigits.isEmpty || rawDigits == '0') {
      state = state.copyWith(error: 'Ingresa un monto mayor a cero');
      return;
    }
    final amount = Decimal.parse(rawDigits);
    if (amount <= Decimal.zero) {
      state = state.copyWith(error: 'El monto debe ser mayor a cero');
      return;
    }

    // Validate account.
    if (s.selectedAccountId == null) {
      state = state.copyWith(error: 'Selecciona una cuenta');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      // 1. Write to local DB immediately (offline-first; no network wait).
      // Anchor the transaction to the LOCAL active period — the same one the
      // Home/Transacciones lists filter by — falling back to the network only
      // when Drift has no period yet (first launch before the first pull).
      // Anchoring to the network period risked a period-id mismatch that made
      // the saved expense invisible to the local-first lists.
      final localPeriod = await ref.read(
        localActiveTrackingPeriodProvider.future,
      );
      final periodId =
          localPeriod?.id ??
          (await ref.read(activeTrackingPeriodProvider.future)).id;
      final localRepo = ref.read(localTransactionRepoProvider);

      // AI accuracy metadata: only record when a suggestion was produced for
      // this capture. `aiCategorized` is true only when the user kept the
      // suggested category; the suggested id + confidence are always stored
      // (when a suggestion existed) so suggested-vs-chosen can be compared.
      final usedAi = s.suggestedCategoryId != null;
      final tx = await localRepo.create(
        trackingPeriodId: periodId,
        accountId: s.selectedAccountId!,
        transactionType: s.transactionType,
        amount: amount,
        categoryId: s.selectedCategoryId,
        description: s.description.trim().isEmpty ? null : s.description.trim(),
        aiCategorized: usedAi && s.selectedCategoryId == s.suggestedCategoryId,
        aiConfidence: usedAi && s.suggestedConfidence != null
            ? Decimal.parse(s.suggestedConfidence!.toStringAsFixed(4))
            : null,
        aiSuggestedCategoryId: s.suggestedCategoryId,
      );
      state = state.copyWith(isLoading: false, savedTransaction: tx);

      // 2. Fire-and-forget push so the outbox row reaches the server if online.
      ref.read(syncControllerProvider.notifier).syncInBackground();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _extractError(e));
    }
  }

  String _extractError(Object e) {
    try {
      // Inline apiErrorMessage logic — avoids importing flutter (no BuildContext).
      // ignore: avoid_dynamic_calls
      final data = (e as dynamic).response?.data;
      if (data is Map && data['error'] is String) {
        return data['error'] as String;
      }
      // ignore: avoid_dynamic_calls
      final msg = (e as dynamic).message as String?;
      if (msg != null) return msg;
    } catch (_) {}
    return e.toString();
  }
}

/// Riverpod 3.x auto-dispose notifier provider. The modal creates a new
/// ProviderScope override so each open gets a fresh controller.
final quickCaptureControllerProvider =
    NotifierProvider.autoDispose<QuickCaptureController, QuickCaptureState>(
      QuickCaptureController.new,
    );
