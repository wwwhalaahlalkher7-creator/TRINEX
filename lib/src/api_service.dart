import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_store.dart';

/// API client for the existing TRINEX backend.
/// Override the base URL at build time using --dart-define=TRINEX_API_BASE_URL=...
class ApiService {
  ApiService({required this.sessionStore, http.Client? client})
      : _client = client ?? http.Client();

  final SessionStore sessionStore;
  final http.Client _client;

  static const _configuredBase = String.fromEnvironment(
    'TRINEX_API_BASE_URL',
    defaultValue: 'https://leo-association-api.www-halaahlalkher7.workers.dev/api/v1',
  );

  Uri _uri(String path) {
    final base = _configuredBase.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (authenticated) {
      final session = await sessionStore.read();
      if (session != null) headers['Authorization'] = 'Bearer ${session.accessToken}';
    }

    final uri = _uri(path);
    late http.Response response;
    try {
      switch (method) {
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(const Duration(seconds: 25));
          break;
        case 'GET':
          response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 25));
          break;
        default:
          throw UnsupportedError('Unsupported HTTP method: $method');
      }
    } on Exception {
      rethrow;
    }

    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(response.body);
      decoded = value is Map<String, dynamic> ? value : <String, dynamic>{};
    } catch (_) {
      decoded = <String, dynamic>{};
    }

    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['success'] == false) {
      final message = decoded['message']?.toString() ??
          decoded['error']?.toString() ??
          'تعذّر تنفيذ الطلب (HTTP ${response.statusCode}).';
      throw ApiServiceException(message, statusCode: response.statusCode);
    }

    final data = decoded['data'];
    if (data is Map<String, dynamic>) return data;
    return decoded;
  }

  Future<AdminSession> login(String userId, String password) async {
    final data = await _request(
      'POST',
      '/auth/staff/login',
      authenticated: false,
      body: {'userId': userId.trim(), 'password': password},
    );
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) throw const ApiServiceException('لم يُرجع الخادم رمز جلسة صالحًا.');
    final expires = int.tryParse(data['expiresInSeconds']?.toString() ?? '') ?? 900;
    final session = AdminSession(
      accessToken: token,
      refreshToken: data['refreshToken']?.toString(),
      displayName: data['staffDisplayName']?.toString() ?? userId.trim(),
      role: data['staffRole']?.toString() ??
          data['role_name']?.toString() ??
          data['staffRoleId']?.toString() ??
          '',
      expiresAt: DateTime.now().add(Duration(seconds: expires)),
    );
    await sessionStore.save(session);
    return session;
  }

  Future<void> logout() async {
    final session = await sessionStore.read();
    if (session != null) {
      try {
        await _client.post(
          _uri('/auth/logout'),
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        // Local logout must work even if the server is unreachable.
      }
    }
    await sessionStore.clear();
  }

  Future<Map<String, dynamic>> getDashboardOverview() =>
      _request('GET', '/admin/dashboard/overview');

  Future<Map<String, dynamic>> getEinoUsage({int hours = 24}) =>
      _request('GET', '/admin/security/eino-usage?hours=${hours.clamp(1, 168)}');

  Future<bool> checkHealth() async {
    try {
      await _request('GET', '/health', authenticated: false);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class ApiServiceException implements Exception {
  const ApiServiceException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
