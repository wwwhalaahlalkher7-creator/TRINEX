import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AdminSession {
  const AdminSession({
    required this.accessToken,
    required this.displayName,
    required this.role,
    required this.expiresAt,
    this.refreshToken,
  });

  final String accessToken;
  final String displayName;
  final String role;
  final DateTime expiresAt;
  final String? refreshToken;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, Object?> toJson() => {
        'accessToken': accessToken,
        'displayName': displayName,
        'role': role,
        'expiresAt': expiresAt.toIso8601String(),
        'refreshToken': refreshToken,
      };

  static AdminSession? fromJson(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AdminSession(
        accessToken: map['accessToken'] as String,
        displayName: map['displayName'] as String? ?? 'مشرف',
        role: map['role'] as String? ?? '',
        expiresAt: DateTime.parse(map['expiresAt'] as String),
        refreshToken: map['refreshToken'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class SessionStore {
  static const _key = 'trinex_admin_session_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<AdminSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final session = AdminSession.fromJson(raw);
    if (session == null || session.isExpired) {
      await clear();
      return null;
    }
    return session;
  }

  Future<void> save(AdminSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
