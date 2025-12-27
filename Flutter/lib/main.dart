import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/lego_theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: LegoEPaperApp()));
}

/// Main application widget
class LegoEPaperApp extends StatelessWidget {
  const LegoEPaperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEGO E-Ink Controller',
      debugShowCheckedModeBanner: false,
      theme: LegoTheme.light,
      home: const HomeScreen(),
    );
  }
}
