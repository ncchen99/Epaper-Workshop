import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'theme/lego_theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const ProviderScope(child: LegoEPaperApp()));
}

/// Main application widget
class LegoEPaperApp extends StatelessWidget {
  const LegoEPaperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Ink Controller',
      debugShowCheckedModeBanner: false,
      theme: LegoTheme.light,
      home: const HomeScreen(),
    );
  }
}
