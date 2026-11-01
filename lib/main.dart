import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/camera_list_screen.dart';
import 'screens/detections_screen.dart';
import 'services/event_service.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  ThemeController.load();
  EventService.instance.load();
  EventService.instance.onDetection.listen(_showDetectionBanner);
  runApp(const KameryApp());
}

/// Powiadomienie w aplikacji: zdjęcie z chwili wykrycia, dotknięcie „Pokaż” otwiera je w całości.
void _showDetectionBanner(Detection d) {
  final messenger = messengerKey.currentState;
  if (messenger == null) return;
  final image = d.image;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
      content: Row(
        children: [
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(image, width: 64, height: 40, fit: BoxFit.cover),
            ),
          if (image != null) const SizedBox(width: 12),
          Expanded(
            child: Text('${d.kind}: ${d.camera.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      action: SnackBarAction(
        label: 'Pokaż',
        onPressed: () {
          final ctx = navigatorKey.currentState?.overlay?.context;
          if (ctx != null) showDetection(ctx, d);
        },
      ),
    ),
  );
}

class KameryApp extends StatelessWidget {
  const KameryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'AriView',
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        debugShowCheckedModeBanner: false,
        locale: const Locale('pl'),
        supportedLocales: const [Locale('pl')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        home: const CameraListScreen(),
      ),
    );
  }
}
