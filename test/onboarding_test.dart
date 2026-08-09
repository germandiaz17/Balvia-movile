/// Tests for the first-run onboarding wizard.
///
/// Two things are load-bearing and easy to break silently:
///  - the pending flag is per-user, so signing into a second account on the
///    same device must not inherit the first user's wizard;
///  - `PUT /accounts/:id` only accepts `initial_balance` while the account has
///    no movements, so the key must be *absent* — not null — whenever the
///    caller is not restating the opening balance.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:balvia_mobile/data/repositories/account_repository.dart';
import 'package:balvia_mobile/features/onboarding/onboarding_controller.dart';

import 'fake_http_adapter.dart';

void main() {
  Map<String, dynamic> accountJson({String name = 'Efectivo'}) =>
      <String, dynamic>{
        'id': 'acc-1',
        'name': name,
        'account_type': 'cash',
        'currency': 'COP',
        'current_balance': '250000',
        'is_archived': false,
        'icon': 'wallet',
        'color': null,
      };

  group('OnboardingController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('starts clean', () {
      expect(container().read(onboardingControllerProvider), isFalse);
    });

    test('registering leaves the wizard owed', () async {
      final c = container();
      await c.read(onboardingControllerProvider.notifier).markPending('user-1');

      expect(c.read(onboardingControllerProvider), isTrue);
    });

    test('finishing (or skipping) clears it for good', () async {
      final c = container();
      final ctrl = c.read(onboardingControllerProvider.notifier);

      await ctrl.markPending('user-1');
      await ctrl.complete();
      expect(c.read(onboardingControllerProvider), isFalse);

      // A relaunch must not resurrect it.
      await ctrl.restoreFor('user-1');
      expect(c.read(onboardingControllerProvider), isFalse);
    });

    test('a wizard left half-done is resumed on next launch', () async {
      final c = container();
      await c.read(onboardingControllerProvider.notifier).markPending('user-1');

      // Simulate a relaunch: fresh container, same SharedPreferences.
      final relaunched = container();
      await relaunched
          .read(onboardingControllerProvider.notifier)
          .restoreFor('user-1');

      expect(relaunched.read(onboardingControllerProvider), isTrue);
    });

    test('another user does not inherit the pending wizard', () async {
      final c = container();
      final ctrl = c.read(onboardingControllerProvider.notifier);

      await ctrl.markPending('user-1');
      await ctrl.restoreFor('user-2');
      expect(c.read(onboardingControllerProvider), isFalse);

      // ...and the stale flag is dropped, not just ignored, so user-1 signing
      // back in does not get the wizard again either.
      await ctrl.restoreFor('user-1');
      expect(c.read(onboardingControllerProvider), isFalse);
    });
  });

  group('AccountRepository.update', () {
    test('sends initial_balance when the wizard restates it', () async {
      final adapter = FakeHttpAdapter([FakeResponse(body: accountJson())]);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;

      await AccountRepository(dio).update(
        'acc-1',
        name: 'Efectivo',
        accountType: 'cash',
        initialBalance: '250000',
      );

      expect(adapter.request.method, 'PUT');
      expect(adapter.request.path, '/accounts/acc-1');
      expect(adapter.request.body!['initial_balance'], '250000');
    });

    test('omits the key entirely on an ordinary rename', () async {
      final adapter = FakeHttpAdapter([
        FakeResponse(body: accountJson(name: 'Bolsillo')),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;

      await AccountRepository(
        dio,
      ).update('acc-1', name: 'Bolsillo', accountType: 'cash');

      // A null would be parsed as "restate the balance to nothing" — the key
      // must not be there at all.
      expect(adapter.request.body!.containsKey('initial_balance'), isFalse);
      expect(adapter.request.body!['name'], 'Bolsillo');
    });

    // The PUT is a full replace: a caller that does not echo the icon back
    // wipes it. This bit the onboarding wizard, which edits the account the
    // backend seeds with icon "wallet".
    test('carries the icon through so a rename does not wipe it', () async {
      final adapter = FakeHttpAdapter([FakeResponse(body: accountJson())]);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;

      await AccountRepository(
        dio,
      ).update('acc-1', name: 'Efectivo', accountType: 'cash', icon: 'wallet');

      expect(adapter.request.body!['icon'], 'wallet');
    });
  });
}
