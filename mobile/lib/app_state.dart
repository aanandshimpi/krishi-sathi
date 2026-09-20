import 'dart:async';

import 'package:flutter/foundation.dart';

import 'services/api_client.dart';
import 'services/location_service.dart';

class AppState extends ChangeNotifier {
  final ApiClient api;
  final LocationService gps;
  Map<String, dynamic>? user, ownTeam;
  List<Map<String, dynamic>> teams = [], bookings = [];
  Map<String, dynamic> adminCounts = {};
  List<Map<String, dynamic>> adminUsers = [],
      adminTeams = [],
      adminBookings = [],
      adminEvents = [];
  FarmLocation? location;
  bool loading = true, marathi = false, liveLocation = false;
  bool foreground = true;
  String? error;
  String crop = 'All crops';
  int radius = 10;
  StreamSubscription<FarmLocation>? _locationSub;
  bool _updatingLocation = false;
  int _teamRequest = 0;
  int _epoch = 0;
  bool _disposed = false;
  AppState({ApiClient? api, LocationService? gps})
    : api = api ?? ApiClient(),
      gps = gps ?? LocationService();
  String tr(String en, String mr) => marathi ? mr : en;
  bool get provider => user?['role'] == 'provider';
  bool get admin => user?['role'] == 'admin';
  void language() {
    marathi = !marathi;
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await api.restore();
      if (api.token != null) {
        user = (await api.request('/me'))['user'] as Map<String, dynamic>;
        if (user!['lat'] != null) {
          location = FarmLocation(
            (user!['lat'] as num).toDouble(),
            (user!['lng'] as num).toDouble(),
          );
        }
        await loadAccountData();
      }
    } catch (e) {
      error = e.toString();
    }
    await loadTeams();
  }

  Future<void> authenticate(
    Map<String, dynamic> body, {
    bool register = false,
    bool adminLogin = false,
  }) async {
    final result = await api.request(
      adminLogin ? '/admin/login' : '/auth/${register ? 'register' : 'login'}',
      method: 'POST',
      body: body,
    );
    await acceptAuthResult(result);
  }

  Future<void> requestOtp(String phone) async {
    await api.request(
      '/auth/otp/request',
      method: 'POST',
      body: {'phone': phone},
    );
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async {
    final result = await api.request(
      '/auth/otp/verify',
      method: 'POST',
      body: {'phone': phone, 'code': code},
    );
    if (result['needsProfile'] != true) await acceptAuthResult(result);
    return result;
  }

  Future<void> completeOtp(Map<String, dynamic> body) async {
    final result = await api.request(
      '/auth/otp/complete',
      method: 'POST',
      body: body,
    );
    await acceptAuthResult(result);
  }

  Future<void> acceptAuthResult(Map<String, dynamic> result) async {
    await api.saveToken(result['token'] as String);
    user = result['user'] as Map<String, dynamic>;
    location = user!['lat'] != null
        ? FarmLocation(
            (user!['lat'] as num).toDouble(),
            (user!['lng'] as num).toDouble(),
          )
        : null;
    notifyListeners();
    await loadAccountData();
    await loadTeams();
  }

  Future<void> loadAccountData() async {
    if (user == null) return;
    if (admin) {
      if (user!['mustChangePassword'] != true) await loadAdminData();
      return;
    }
    bookings = List<Map<String, dynamic>>.from(
      (await api.request('/bookings'))['bookings'] as List,
    );
    if (provider) {
      ownTeam =
          (await api.request('/provider/team'))['team']
              as Map<String, dynamic>?;
    }
    notifyListeners();
  }

  Future<void> loadAdminData() async {
    if (!admin || user!['mustChangePassword'] == true) return;
    final results = await Future.wait([
      api.request('/admin/overview'),
      api.request('/admin/users'),
      api.request('/admin/teams'),
      api.request('/admin/bookings'),
      api.request('/admin/audit'),
    ]);
    adminCounts = results[0]['counts'] as Map<String, dynamic>;
    adminUsers = List<Map<String, dynamic>>.from(results[1]['users'] as List);
    adminTeams = List<Map<String, dynamic>>.from(results[2]['teams'] as List);
    adminBookings = List<Map<String, dynamic>>.from(
      results[3]['bookings'] as List,
    );
    adminEvents = List<Map<String, dynamic>>.from(results[4]['events'] as List);
    notifyListeners();
  }

  Future<void> changeAdminPassword(String current, String next) async {
    user =
        (await api.request(
              '/admin/password',
              method: 'PATCH',
              body: {'currentPassword': current, 'newPassword': next},
            ))['user']
            as Map<String, dynamic>;
    notifyListeners();
    await loadAdminData();
  }

  Future<void> setAdminUserSuspended(int id, bool suspended) async {
    await api.request(
      '/admin/users/$id',
      method: 'PATCH',
      body: {'suspended': suspended},
    );
    await loadAdminData();
  }

  Future<void> setAdminTeam(int id, Map<String, dynamic> changes) async {
    await api.request('/admin/teams/$id', method: 'PATCH', body: changes);
    await loadAdminData();
  }

  Future<void> adminCancelBooking(int id, String reason) async {
    await api.request(
      '/admin/bookings/$id/cancel',
      method: 'POST',
      body: {'reason': reason},
    );
    await loadAdminData();
  }

  Future<void> loadTeams() async {
    final request = ++_teamRequest;
    loading = true;
    error = null;
    notifyListeners();
    final params = <String, String>{
      'crop': crop,
      if (location != null) 'lat': '${location!.lat}',
      if (location != null) 'lng': '${location!.lng}',
      'radius': '$radius',
    };
    try {
      final data = await api.request(
        '/teams?${Uri(queryParameters: params).query}',
      );
      if (request != _teamRequest) return;
      teams = List<Map<String, dynamic>>.from(data['teams'] as List);
    } catch (e) {
      if (request == _teamRequest) {
        error = e.toString();
        teams = [];
      }
    }
    if (request == _teamRequest) {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setLocation(FarmLocation value) async {
    final generation = _epoch;
    if (user != null) {
      final result = await api.request(
        '/me',
        method: 'PATCH',
        body: value.toJson(),
      );
      if (_epoch != generation || _disposed) return;
      user = result['user'] as Map<String, dynamic>;
    }
    if (_epoch != generation || _disposed) return;
    location = value;
    notifyListeners();
    await loadTeams();
  }

  Future<void> setLiveLocation(bool enabled) async {
    await stopLocationUpdates();
    if (enabled) await gps.ensurePermission();
    liveLocation = enabled;
    notifyListeners();
    if (enabled) resumeLocationUpdates();
  }

  void resumeLocationUpdates() {
    if (!liveLocation || _locationSub != null) return;
    _locationSub = gps.updates().listen(
      (p) async {
        if (_updatingLocation) return;
        _updatingLocation = true;
        try {
          await setLocation(p);
        } catch (e) {
          error = e.toString();
          notifyListeners();
        } finally {
          _updatingLocation = false;
        }
      },
      onError: (Object e) {
        error = e.toString();
        liveLocation = false;
        unawaited(stopLocationUpdates());
        notifyListeners();
      },
    );
  }

  Future<void> stopLocationUpdates() async {
    await _locationSub?.cancel();
    _locationSub = null;
  }

  Future<void> publishTeam(Map<String, dynamic> body) async {
    ownTeam =
        (await api.request('/provider/team', method: 'PUT', body: body))['team']
            as Map<String, dynamic>;
    await loadTeams();
    notifyListeners();
  }

  Future<void> requestBooking(Map<String, dynamic> body) async {
    await api.request('/bookings', method: 'POST', body: body);
    await loadAccountData();
  }

  Future<void> shareLocation(int id, bool enabled) async {
    if (enabled) {
      final p = await gps.current();
      await setLocation(p);
      await setLiveLocation(true);
    }
    await api.request(
      '/bookings/$id/location-sharing',
      method: 'PATCH',
      body: {'enabled': enabled},
    );
    await loadAccountData();
    if (!enabled && !bookings.any((b) => b['locationSharing'] == true)) {
      await setLiveLocation(false);
    }
  }

  Future<void> status(int id, String value) async {
    await api.request(
      '/bookings/$id/status',
      method: 'PATCH',
      body: {'status': value},
    );
    await loadAccountData();
  }

  Future<void> logout() async {
    // Revoke on the server before discarding the local session.
    try {
      await api.request('/auth/logout', method: 'POST', body: {});
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
    }
    _epoch++;
    await api.clearToken();
    await stopLocationUpdates();
    user = null;
    ownTeam = null;
    bookings = [];
    location = null;
    liveLocation = false;
    await loadTeams();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(stopLocationUpdates());
    api.dispose();
    super.dispose();
  }
}
