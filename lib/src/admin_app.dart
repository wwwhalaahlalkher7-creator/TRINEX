import 'package:flutter/material.dart';
import 'api_service.dart';
import 'session_store.dart';
import 'shell.dart';

class TrinexAdminApp extends StatefulWidget {
  const TrinexAdminApp({super.key});

  @override
  State<TrinexAdminApp> createState() => _TrinexAdminAppState();
}

class _TrinexAdminAppState extends State<TrinexAdminApp> {
  late final SessionStore _sessionStore = SessionStore();
  late final ApiService _api = ApiService(sessionStore: _sessionStore);

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF246BFD);
    return MaterialApp(
      title: 'TRINEX Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE6EAF1)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFD),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE3ED)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE3ED)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
      ),
      home: AdminShell(api: _api, sessionStore: _sessionStore),
    );
  }
}
