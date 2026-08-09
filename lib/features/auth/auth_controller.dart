import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../data/models/user.dart';
import '../onboarding/onboarding_controller.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Auth state: a status plus the current user when authenticated.
class AuthState {
  const AuthState(this.status, [this.user]);
  final AuthStatus status;
  final User? user;
}

/// Owns the authentication lifecycle. On creation it bootstraps from stored
/// tokens; exposes login/register/logout used by the UI.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Flip to logged-out if the API client reports an expired session.
    ref.listen(sessionExpiredProvider, (_, _) {
      state = const AuthState(AuthStatus.unauthenticated);
    });
    _bootstrap();
    return const AuthState(AuthStatus.unknown);
  }

  /// SharedPreferences key recording which user's data lives in the local DB.
  static const _kLocalDataOwnerKey = 'local_data_owner_user_id';

  /// Ensures the local DB belongs to [user]. If another user's data (or an
  /// unknown owner's) is cached, wipe it — including the sync cursor — so the
  /// next pull re-downloads this user's data from scratch. Without this, a
  /// user switch both leaks the previous user's rows and leaves a cursor that
  /// makes the pull skip anything older than the previous sync.
  Future<void> _adoptLocalData(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString(_kLocalDataOwnerKey);
    if (owner != user.id) {
      await ref.read(appDatabaseProvider).clearAllData();
      await prefs.setString(_kLocalDataOwnerKey, user.id);
    }
  }

  Future<void> _bootstrap() async {
    final token = await ref.read(tokenStorageProvider).accessToken();
    if (token == null) {
      state = const AuthState(AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await ref.read(authRepositoryProvider).me();
      await _adoptLocalData(user);
      // Resume the first-run wizard if the user quit halfway through it.
      await ref.read(onboardingControllerProvider.notifier).restoreFor(user.id);
      state = AuthState(AuthStatus.authenticated, user);
    } catch (_) {
      state = const AuthState(AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    final user = await ref
        .read(authRepositoryProvider)
        .login(email: email, password: password);
    await _adoptLocalData(user);
    await ref.read(onboardingControllerProvider.notifier).restoreFor(user.id);
    state = AuthState(AuthStatus.authenticated, user);
  }

  Future<void> register(String email, String password, String? fullName) async {
    final user = await ref
        .read(authRepositoryProvider)
        .register(email: email, password: password, fullName: fullName);
    await _adoptLocalData(user);
    // Flag before flipping to authenticated: the router reads this
    // synchronously on the very redirect that the state change triggers.
    await ref.read(onboardingControllerProvider.notifier).markPending(user.id);
    state = AuthState(AuthStatus.authenticated, user);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState(AuthStatus.unauthenticated);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
