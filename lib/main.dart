import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/camera_list_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const KameryApp());
}

class KameryApp extends StatelessWidget {
  const KameryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kamery HD',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // Obraz z kamer najlepiej wygląda na ciemnym tle - ciemny motyw jest domyślny.
      themeMode: ThemeMode.dark,
      home: const CameraListScreen(),
    );
  }
}
