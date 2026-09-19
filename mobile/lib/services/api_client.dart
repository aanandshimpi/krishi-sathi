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
  static const configuredUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );
  static const allowLocalHttp = bool.fromEnvironment('ALLOW_LOCAL_HTTP');
  final String baseUrl;
  final http.Client client;
  final FlutterSecureStorage storage;
  final Duration requestTimeout;
  String? token;
  ApiClient({
    this.baseUrl = configuredUrl,
    this.requestTimeout = const Duration(seconds: 20),
    http.Client? client,
    FlutterSecureStorage? storage,
  }) : client = client ?? http.Client(),
       storage = storage ?? const FlutterSecureStorage();

  Future<void> restore() async {
    token = await storage.read(key: 'session');
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
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'The service took too long. Check your connection and retry.',
      );
    } on FormatException {
      throw const ApiException('The service returned an invalid response.');
    } on Exception {
      throw const ApiException(
        'Cannot connect. Check your internet connection and retry.',
      );
    }
  }

  void dispose() => client.close();
}
