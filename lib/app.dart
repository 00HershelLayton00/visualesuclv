import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'globals.dart';
import 'screens/home_shell.dart';
import 'services/settings_service.dart';
import 'theme.dart';

class VisualesApp extends StatelessWidget {
  const VisualesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<SettingsService>().themeMode;
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: themeMode,
      home: const HomeShell(),
    );
  }
}
