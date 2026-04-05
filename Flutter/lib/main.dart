import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'theme/lego_theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
      debugPrint('FlutterError stack: ${details.stack}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('PlatformDispatcher error: $error');
      debugPrint('PlatformDispatcher stack: $stack');
      return true;
    };

    await dotenv.load(fileName: '.env');

    runApp(const ProviderScope(child: LegoEPaperApp()));
  }, (error, stack) {
    debugPrint('runZonedGuarded error: $error');
    debugPrint('runZonedGuarded stack: $stack');
  });
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
