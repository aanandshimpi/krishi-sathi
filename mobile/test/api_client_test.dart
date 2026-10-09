import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:krishi_saathi/services/api_client.dart';

class MemoryApi extends ApiClient {
  MemoryApi({required super.client, super.requestTimeout})
    : super(baseUrl: 'https://example.test');
  @override
  Future<void> clearToken() async {
    token = null;
  }
}

void main() {
  test('authenticated requests send JSON to the configured backend', () async {
    final api = MemoryApi(
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/api/bookings');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer session-token');
        expect(jsonDecode(request.body)['workers'], 4);
        return http.Response('{"booking":{"id":12,"status":"pending"}}', 201);
      }),
    )..token = 'session-token';
    expect(
      (await api.request(
        '/bookings',
        method: 'POST',
        body: {'workers': 4},
      ))['booking']['status'],
      'pending',
    );
    api.dispose();
  });
  test('capacity conflicts expose the server message', () async {
    final api = MemoryApi(
      client: MockClient(
        (_) async => http.Response(
          '{"error":"Not enough workers are available on this date."}',
          409,
        ),
      ),
    );
    await expectLater(
      api.request('/bookings', method: 'POST', body: {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having(
              (e) => e.message,
              'message',
              contains('Not enough workers'),
            ),
      ),
    );
    api.dispose();
  });
  test('connection stalls time out before the response arrives', () async {
    final response = Completer<http.Response>();
    final api = MemoryApi(
      client: MockClient((_) => response.future),
      requestTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      api.request('/teams'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('took too long'),
        ),
      ),
    );
    response.complete(http.Response('{"teams":[]}', 200));
    api.dispose();
  });
  test('expired sessions clear the stored token', () async {
    final api = MemoryApi(
      client: MockClient(
        (_) async => http.Response('{"error":"Please sign in."}', 401),
      ),
    )..token = 'expired';
    await expectLater(api.request('/me'), throwsA(isA<ApiException>()));
    expect(api.token, isNull);
    api.dispose();
  });
}
