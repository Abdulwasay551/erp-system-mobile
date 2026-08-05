import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

// Matches the web app's shadcn/ui "neutral" theme (flat black/white, ~10px corners)
// instead of Material 3's default seed-based tonal palette, which tints even a
// near-black seed with a faint purple/blue hue - the two apps ended up looking like
// different products because of it.
const _ink = Color(0xFF171717);
const _border = Color(0xFFE5E5E5);
const _radius = 10.0;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthService(),
      child: MaterialApp(
        title: 'Mobile Corner ERP',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(seedColor: _ink, brightness: Brightness.light).copyWith(
            primary: _ink,
            onPrimary: Colors.white,
            primaryContainer: _ink,
            onPrimaryContainer: Colors.white,
            secondaryContainer: const Color(0xFFF5F5F5),
            onSecondaryContainer: _ink,
            surface: Colors.white,
            surfaceContainerHighest: const Color(0xFFF5F5F5),
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: _ink,
            foregroundColor: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: _ink,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
              side: const BorderSide(color: _border),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: _ink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius - 2)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: _border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius - 2)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_radius - 2),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_radius - 2),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_radius - 2),
              borderSide: const BorderSide(color: _ink, width: 1.5),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: _ink.withValues(alpha: 0.08),
            surfaceTintColor: Colors.transparent,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
                color: states.contains(WidgetState.selected) ? _ink : Colors.grey.shade600,
              ),
            ),
          ),
          dividerTheme: const DividerThemeData(color: _border),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
  }
}
