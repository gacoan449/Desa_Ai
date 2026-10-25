import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  try {
    await Firebase.initializeApp();
  } catch (error) {
    startupError = error;
  }
  runApp(DesaAiApp(startupError: startupError));
}

class DesaAiApp extends StatelessWidget {
  const DesaAiApp({super.key, this.startupError});
  final Object? startupError;

  static const ink = Color(0xFF18251F);
  static const green = Color(0xFF157A52);
  static const canvas = Color(0xFFF7F8F6);

  @override
  Widget build(BuildContext context) {
    if (startupError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: _SetupErrorScreen(message: startupError.toString()),
      );
    }
    return MaterialApp(
      title: 'Desa AI',
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: const AuthGate(),
    );
  }

  ThemeData _theme() => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: green,
      brightness: Brightness.light,
      primary: green,
      surface: Colors.white,
    ),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: Color(0xFF929A95), fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E9E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E9E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: green, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: Color(0xFFE0E6E0)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == null) return const LoginScreen();
        return const WorkspaceScreen();
      },
    );
  }
}

class _SetupErrorScreen extends StatelessWidget {
  const _SetupErrorScreen({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(color: const Color(0xFFE6F3EB), borderRadius: BorderRadius.circular(24)),
                  child: const Icon(Icons.auto_awesome_rounded, size: 38, color: DesaAiApp.green),
                ),
                const SizedBox(height: 22),
                const Text('Sambungkan Firebase terlebih dahulu', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: DesaAiApp.ink)),
                const SizedBox(height: 10),
                const Text('Buat project Firebase, aktifkan Authentication dan Firestore, lalu jalankan FlutterFire configure. Jangan taruh API key AI di aplikasi.',
                  textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF66716A), height: 1.5)),
                const SizedBox(height: 18),
                SelectableText(message, style: const TextStyle(fontSize: 11, color: Color(0xFF8B918D))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
