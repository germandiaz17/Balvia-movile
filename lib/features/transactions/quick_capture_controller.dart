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
    this.error,
    this.savedTransaction,
  });

  /// Digit string the user has typed on the numeric keypad — no separators.
  final String rawDigits;

  /// "expense" | "income"
  final String transactionType;
  final String? selectedCategoryId;
  final String? selectedAccountId;
  final String description;
  final bool isLoading;
  final String? error;

  /// Set when a transaction has been successfully saved.
  final Transaction? savedTransaction;

  QuickCaptureState copyWith({
    String? rawDigits,
    String? transactionType,
    Object? selectedCategoryId = _sentinel,
    String? selectedAccountId,
    String? description,
    bool? isLoading,
    Object? error = _sentinel,
    Object? savedTransaction = _sentinel,
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
      error: error == _sentinel ? this.error : error as String?,
      savedTransaction: savedTransaction == _sentinel
          ? this.savedTransaction
          : savedTransaction as Transaction?,
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
      final localPeriod = await ref
          .read(localActiveTrackingPeriodProvider.future);
      final periodId =
          localPeriod?.id ??
          (await ref.read(activeTrackingPeriodProvider.future)).id;
      final localRepo = ref.read(localTransactionRepoProvider);
      final tx = await localRepo.create(
        trackingPeriodId: periodId,
        accountId: s.selectedAccountId!,
        transactionType: s.transactionType,
        amount: amount,
        categoryId: s.selectedCategoryId,
        description: s.description.trim().isEmpty ? null : s.description.trim(),
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
