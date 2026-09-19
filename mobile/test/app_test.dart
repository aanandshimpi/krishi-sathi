import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishi_saathi/main.dart';
import 'package:krishi_saathi/admin_page.dart';
import 'package:krishi_saathi/app_state.dart';
import 'package:krishi_saathi/services/api_client.dart';
import 'package:krishi_saathi/services/location_service.dart';

class FakeApi extends ApiClient {
  final calls = <String>[];
  @override
  Future<void> restore() async {}
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    calls.add(path);
    if (path.startsWith('/teams')) return {'teams': <Map<String, dynamic>>[]};
    if (path == '/bookings') return {'bookings': <Map<String, dynamic>>[]};
    throw const ApiException('Not implemented in test');
  }
}

class FakeGps extends LocationService {
  final positions = StreamController<FarmLocation>.broadcast();
  bool deny = false;
  @override
  Future<void> ensurePermission() async {
    if (deny) throw const LocationException('Denied');
  }

  @override
  Future<FarmLocation> current() async {
    await ensurePermission();
    return const FarmLocation(17.65, 75.9);
  }

  @override
  Stream<FarmLocation> updates() => positions.stream;
}

class SharingApi extends FakeApi {
  bool shared = false;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (path == '/me') {
      return {
        'user': {'id': 1, 'role': 'provider', ...?body},
      };
    }
    if (path == '/bookings/12/location-sharing') {
      shared = body!['enabled'] as bool;
      return {};
    }
    if (path == '/bookings') {
      return {
        'bookings': [
          {'id': 12, 'locationSharing': shared},
        ],
      };
    }
    if (path == '/provider/team') return {'team': null};
    return super.request(path, method: method, body: body);
  }
}

class AdminApi extends FakeApi {
  bool suspended = false, verified = false;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    calls.add(path);
    if (path == '/admin/overview') {
      return {
        'counts': {
          'farmers': 1,
          'providers': 1,
          'teams': 1,
          'pendingBookings': 1,
        },
      };
    }
    if (path == '/admin/users') {
      return {
        'users': [
          {
            'id': 2,
            'name': 'Test Farmer',
            'phone': '9000000001',
            'role': 'farmer',
            'address': 'Solapur',
            'suspended': suspended,
          },
        ],
      };
    }
    if (path == '/admin/teams') {
      return {
        'teams': [
          {
            'id': 3,
            'name': 'Test Team',
            'place': 'Solapur',
            'providerName': 'Provider',
            'providerPhone': '9000000002',
            'people': 5,
            'price': 400,
            'skills': ['Harvesting'],
            'verified': verified,
            'adminHidden': false,
          },
        ],
      };
    }
    if (path == '/admin/bookings') {
      return {
        'bookings': [
          {
            'id': 4,
            'team': 'Test Team',
            'farmerName': 'Test Farmer',
            'farmerPhone': '9000000001',
            'providerName': 'Provider',
            'providerPhone': '9000000002',
            'task': 'Harvesting',
            'workers': 2,
            'date': '2026-09-20',
            'total': 800,
            'status': 'pending',
          },
        ],
      };
    }
    if (path == '/admin/audit') return {'events': <Map<String, dynamic>>[]};
    if (path == '/admin/users/2') {
      suspended = body!['suspended'] as bool;
      return {};
    }
    if (path == '/admin/teams/3') {
      verified = body!['verified'] as bool? ?? verified;
      return {};
    }
    if (path == '/admin/password') {
      return {
        'user': {
          'id': 1,
          'name': 'KVK Admin',
          'role': 'admin',
          'mustChangePassword': false,
        },
      };
    }
    return super.request(path, method: method, body: body);
  }
}

void main() {
  testWidgets(
    'farmer home and Marathi navigation render without sample teams',
    (tester) async {
      final state = AppState(api: FakeApi());
      await tester.pumpWidget(KrishiApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('Set farm GPS location'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.textContaining('No teams here yet.'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pumpAndSettle();
      await tester.tap(find.text('मराठी'));
      await tester.pumpAndSettle();
      expect(find.text('मजूर शोधा'), findsOneWidget);
      expect(find.text('शेताचे GPS स्थान ठेवा'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('sign-in validates the mobile number before contacting the API', (
    tester,
  ) async {
    final api = FakeApi();
    final state = AppState(api: api);
    await tester.pumpWidget(MaterialApp(home: AuthPage(state: state)));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a 10-digit Indian number'), findsOneWidget);
    expect(api.calls, isEmpty);
    state.dispose();
  });
  test(
    'foreground GPS updates stop on pause and resume only when enabled',
    () async {
      final gps = FakeGps();
      final state = AppState(api: FakeApi(), gps: gps);
      await state.setLiveLocation(true);
      expect(gps.positions.hasListener, isTrue);
      gps.positions.add(const FarmLocation(17.65, 75.9));
      await Future<void>.delayed(Duration.zero);
      expect(state.location!.lat, 17.65);
      await state.stopLocationUpdates();
      expect(gps.positions.hasListener, isFalse);
      state.resumeLocationUpdates();
      expect(gps.positions.hasListener, isTrue);
      await state.setLiveLocation(false);
      state.resumeLocationUpdates();
      expect(gps.positions.hasListener, isFalse);
      state.dispose();
      await gps.positions.close();
    },
  );
  test(
    'provider sharing obtains GPS and stops updates after consent is removed',
    () async {
      final gps = FakeGps();
      final api = SharingApi();
      final state = AppState(api: api, gps: gps)
        ..user = {'id': 1, 'role': 'provider'};
      await state.shareLocation(12, true);
      expect(api.shared, isTrue);
      expect(gps.positions.hasListener, isTrue);
      await state.shareLocation(12, false);
      expect(api.shared, isFalse);
      expect(gps.positions.hasListener, isFalse);
      state.dispose();
      await gps.positions.close();
    },
  );
  testWidgets('KVK admin sees own dashboard and all team records', (
    tester,
  ) async {
    final api = AdminApi();
    final state = AppState(api: api)
      ..user = {
        'id': 1,
        'name': 'KVK Admin',
        'role': 'admin',
        'mustChangePassword': false,
      };
    await state.loadAdminData();
    await tester.pumpWidget(MaterialApp(home: AdminPage(state: state)));
    expect(find.text('KVK operations'), findsOneWidget);
    await tester.tap(find.text('Teams').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Test Team'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
  test(
    'KVK admin changes temporary password before fetching records',
    () async {
      final api = AdminApi();
      final state = AppState(api: api)
        ..user = {
          'id': 1,
          'name': 'KVK Admin',
          'role': 'admin',
          'mustChangePassword': true,
        };
      await state.loadAccountData();
      expect(api.calls, isEmpty);
      await state.changeAdminPassword('temporary-password', 'new-password-123');
      expect(state.user!['mustChangePassword'], false);
      expect(api.calls, contains('/admin/overview'));
      await state.setAdminUserSuspended(2, true);
      expect(api.suspended, true);
      await state.setAdminTeam(3, {'verified': true});
      expect(api.verified, true);
      state.dispose();
    },
  );
  test('denied GPS permission does not begin tracking', () async {
    final gps = FakeGps()..deny = true;
    final state = AppState(api: FakeApi(), gps: gps);
    await expectLater(
      state.setLiveLocation(true),
      throwsA(isA<LocationException>()),
    );
    expect(state.liveLocation, isFalse);
    expect(gps.positions.hasListener, isFalse);
    state.dispose();
    await gps.positions.close();
  });
}
