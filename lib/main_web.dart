import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env_config.dart';
import 'screens/auth/welcome_screen.dart';
import 'web_app/screens/home_screen.dart';
import 'web_app/services/audio_player_service.dart';

/// Standalone Web Entrypoint
/// Completely decoupled from native desktop/mobile audio plugins (smtc_windows / audio_service)
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvConfig.load();

  if (EnvConfig.supabaseUrl.isNotEmpty && EnvConfig.supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
    );
  }

  await AudioPlayerService().init();
  runApp(
    const ProviderScope(
      child: TeloPlayWebApp(),
    ),
  );
}

class TeloPlayWebApp extends StatefulWidget {
  const TeloPlayWebApp({super.key});

  @override
  State<TeloPlayWebApp> createState() => _TeloPlayWebAppState();
}

class _TeloPlayWebAppState extends State<TeloPlayWebApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeloPlay Web - Pure Music Flow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0B14),
        primaryColor: const Color(0xFF7C3AED),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFFDB2777),
          surface: Color(0xFF14151F),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0B14),
          elevation: 0,
        ),
      ),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = Supabase.instance.client.auth.currentSession;
          if (session != null) {
            return const HomeScreen();
          }
          return const WelcomeScreen();
        },
      ),
    );
  }
}




