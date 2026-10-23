import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int status;
  const ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class ApiClient {
  static const List<String> androidCandidates = [
    'http://192.168.15.160:3001', // Current Wi-Fi IP
    'http://10.170.174.161:3001', // Previous Wi-Fi IP
    'http://10.0.2.2:3001',        // Android Emulator host loopback
    'http://127.0.0.1:3001',       // USB adb reverse
  ];

  static String get defaultBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://localhost:3001';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return androidCandidates.first;
    }
    return 'http://localhost:3001';
  }
  static const allowLocalHttp = bool.fromEnvironment('ALLOW_LOCAL_HTTP', defaultValue: true);
  String baseUrl;
  final http.Client client;
  final FlutterSecureStorage storage;
  final Duration requestTimeout;
  String? token;
  ApiClient({
    String? baseUrl,
    this.requestTimeout = const Duration(seconds: 20),
    http.Client? client,
    FlutterSecureStorage? storage,
  }) : baseUrl = baseUrl ?? defaultBaseUrl,
       client = client ?? http.Client(),
       storage = storage ?? const FlutterSecureStorage();

  Future<void> restore() async {
    token = await storage.read(key: 'session');
    final savedBase = await storage.read(key: 'custom_base_url');
    if (savedBase != null && savedBase.isNotEmpty) {
      baseUrl = savedBase;
    }
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await storage.write(key: 'custom_base_url', value: baseUrl);
  }

  Future<void> saveToken(String value) async {
    await storage.write(key: 'session', value: value);
    token = value;
  }

  Future<void> clearToken() async {
    token = null;
    await storage.delete(key: 'session');
  }

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) => _requestWithFallback(path, method: method, body: body);

  Future<Map<String, dynamic>> _requestWithFallback(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Set<String>? triedUrls,
  }) async {
    final uri = Uri.parse('$baseUrl/api$path');
    if (kReleaseMode && !allowLocalHttp && uri.scheme != 'https') {
      throw const ApiException(
        'The live service must use a secure HTTPS address.',
      );
    }
    try {
      final req = http.Request(method, uri);
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final response = await client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(requestTimeout);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        if (response.statusCode == 401) await clearToken();
        throw ApiException(
          data['error'] as String? ?? 'Please try again.',
          response.statusCode,
        );
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          unawaited(storage.write(key: 'custom_base_url', value: baseUrl).catchError((_) {}));
        } catch (_) {}
      }
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'The service took too long. Check your connection and retry.',
      );
    } on FormatException {
      throw const ApiException('The service returned an invalid response.');
    } on Exception catch (e) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final tried = triedUrls ?? {baseUrl};
        for (final candidate in androidCandidates) {
          if (!tried.contains(candidate)) {
            baseUrl = candidate;
            tried.add(candidate);
            debugPrint('ApiClient retrying with fallback: $candidate');
            return _requestWithFallback(
              path,
              method: method,
              body: body,
              triedUrls: tried,
            );
          }
        }
      }
      debugPrint('ApiClient connection error: $e');
      throw const ApiException(
        'Cannot connect. Check your internet connection and retry.',
      );
    }
  }

  void dispose() => client.close();
}
