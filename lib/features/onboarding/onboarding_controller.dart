import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the signed-in user still owes the first-run wizard.
///
/// This is UI state, not domain state, so it lives in SharedPreferences rather
/// than in a `user_settings` column: re-showing a three-screen wizard after a
/// reinstall is harmless, and a migration would not earn its keep.
///
/// It is keyed by user id so that signing into a different account on the same
/// device does not inherit the previous user's pending flag.
class OnboardingController extends Notifier<bool> {
  static const _kPendingUserKey = 'pending_onboarding_user_id';

  /// True while the wizard is owed. Read synchronously by the router redirect,
  /// so it must never be a Future.
  @override
  bool build() => false;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Marks the wizard as owed. Called right after a successful registration.
  Future<void> markPending(String userId) async {
    state = true;
    await (await _prefs).setString(_kPendingUserKey, userId);
  }

  /// Restores the flag on login/bootstrap. A flag belonging to another user is
  /// dropped rather than honoured.
  Future<void> restoreFor(String userId) async {
    final prefs = await _prefs;
    final pendingFor = prefs.getString(_kPendingUserKey);
    if (pendingFor != null && pendingFor != userId) {
      await prefs.remove(_kPendingUserKey);
      state = false;
      return;
    }
    state = pendingFor == userId;
  }

  /// Clears the flag — whether the user finished the wizard or skipped it.
  /// Skipping is allowed on purpose: the backend already guarantees a usable
  /// account exists, so nothing here is load-bearing.
  Future<void> complete() async {
    state = false;
    await (await _prefs).remove(_kPendingUserKey);
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);
