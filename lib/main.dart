import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'globals.dart';
import 'services/background_service.dart';
import 'services/directory_service.dart';
import 'services/download_manager.dart';
import 'services/favorites_service.dart';
import 'services/notification_service.dart';
import 'services/public_storage.dart';
import 'services/search_index_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();

  final notifications = NotificationService();
  await notifications.init(
    onTap: (payload) {
      pendingNotificationPayload.value = payload;
    },
  );

  final api = ApiClient(preferences);
  final directories = DirectoryService(api);
  final searchIndex = SearchIndexService(api);
  final favorites = FavoritesService(directories, notifications);
  final downloads = DownloadManager(api, notifications);
  final settings = SettingsService(preferences);

  await favorites.load();
  await downloads.load();
  await PublicStorage.detect();
  await BackgroundService.initialize();

  final launchPayload = await notifications.launchPayload();
  if (launchPayload != null) {
    pendingNotificationPayload.value = launchPayload;
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<DirectoryService>.value(value: directories),
        Provider<NotificationService>.value(value: notifications),
        ChangeNotifierProvider<SearchIndexService>.value(value: searchIndex),
        ChangeNotifierProvider<FavoritesService>.value(value: favorites),
        ChangeNotifierProvider<DownloadManager>.value(value: downloads),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
      ],
      child: const VisualesApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    notifications.requestPermission();
  });
}
