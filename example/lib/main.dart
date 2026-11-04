import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'desktop_screen.dart';
import 'web_analyzer_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late bool _showWebAnalyzer;

  @override
  void initState() {
    super.initState();
    // Default to the Web Audio Tag Analyzer on web, Desktop Screen on desktop
    _showWebAnalyzer = kIsWeb;
  }

  void _toggleScreen() {
    setState(() {
      _showWebAnalyzer = !_showWebAnalyzer;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Tag Analyzer',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Indigo
          brightness: Brightness.dark,
          surface: const Color(0xFF1E293B), // Slate 800
          primary: const Color(0xFF818CF8), // Indigo 400
          secondary: const Color(0xFF38BDF8), // Sky 400
          tertiary: const Color(0xFF34D399), // Emerald 400
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF334155), width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF475569)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
        ),
      ),
      home: _showWebAnalyzer
          ? WebAnalyzerScreen(onSwitchToDesktop: _toggleScreen)
          : DesktopScreen(onSwitchToAnalyzer: _toggleScreen),
      debugShowCheckedModeBanner: false,
    );
  }
}
