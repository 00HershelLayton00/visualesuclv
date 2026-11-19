import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../core/api_client.dart';
import 'directory_service.dart';
import 'favorites_service.dart';
import 'notification_service.dart';

const String backgroundTaskName = 'checkFavorites';
const String backgroundUniqueName = 'visuales-favorites-check';

/// Punto de entrada del aislado en segundo plano (WorkManager).
@pragma('vm:entry-point')
void visualesBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != backgroundTaskName) return true;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getBool('background_checks') == false) return true;
      final notifications = NotificationService();
      await notifications.init();
      final api = ApiClient(preferences);
      final directories = DirectoryService(api);
      final favorites = FavoritesService(directories, notifications);
      await favorites.load();
      await favorites.checkAll(notify: true);
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// Programa la revision periodica de carpetas favoritas.
class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(visualesBackgroundDispatcher);
    await enable();
  }

  static Future<void> enable() async {
    try {
      await Workmanager().registerPeriodicTask(
        backgroundUniqueName,
        backgroundTaskName,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 10),
      );
    } catch (_) {
      // La app funciona igual sin revision en segundo plano.
    }
  }

  static Future<void> disable() async {
    try {
      await Workmanager().cancelByUniqueName(backgroundUniqueName);
    } catch (_) {
      // Ignorar.
    }
  }
}
