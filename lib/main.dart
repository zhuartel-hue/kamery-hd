import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/camera_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const KameryApp());
}

class KameryApp extends StatelessWidget {
  const KameryApp({super.key});

  static const seed = Color(0xFF1F3A5F);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kamery HD',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const CameraListScreen(),
    );
  }
}
