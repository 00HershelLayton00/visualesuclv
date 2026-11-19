import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef NotificationTapCallback = void Function(String payload);

/// Notificaciones locales para cambios en favoritos y descargas.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  NotificationTapCallback? _onTap;
  bool _initialized = false;

  static const String changesChannelId = 'favorite_changes';
  static const String downloadsChannelId = 'downloads';

  Future<void> init({NotificationTapCallback? onTap}) async {
    if (onTap != null) _onTap = onTap;
    if (_initialized) return;
    const android = AndroidInitializationSettings('ic_stat_visuales');
    const settings = InitializationSettings(android: android);
    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            _onTap?.call(payload);
          }
        },
      );
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<void> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    } catch (_) {
      // Sin permiso: las notificaciones simplemente no se mostraran.
    }
  }

  /// Payload si la app fue abierta tocando una notificacion.
  Future<String?> launchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        return details?.notificationResponse?.payload;
      }
    } catch (_) {
      // Ignorar.
    }
    return null;
  }

  Future<void> showChange({
    required String folderName,
    required String folderUrl,
    required String body,
  }) {
    return _show(
      id: folderUrl.hashCode & 0x7fffffff,
      title: folderName,
      body: body,
      payload: 'folder:$folderUrl',
      channelId: changesChannelId,
      channelName: 'Cambios en favoritos',
      channelDescription:
          'Avisa cuando una carpeta favorita cambia o desaparece',
      highPriority: true,
      groupKey: 'cu.uclv.visuales.changes',
    );
  }

  Future<void> showDownloadFinished({
    required String fileName,
    required String target,
    required String details,
  }) {
    return _show(
      id: ('download:$target').hashCode & 0x7fffffff,
      title: 'Descarga completada',
      body: '$fileName ($details)\nToca para abrir',
      payload: target,
      channelId: downloadsChannelId,
      channelName: 'Descargas',
      channelDescription: 'Avisos de descargas completadas',
      highPriority: false,
      groupKey: 'cu.uclv.visuales.downloads',
    );
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String payload,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required bool highPriority,
    String? groupKey,
  }) async {
    if (!_initialized) {
      await init();
      if (!_initialized) return;
    }
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            icon: 'ic_stat_visuales',
            importance: highPriority
                ? Importance.high
                : Importance.defaultImportance,
            priority: highPriority ? Priority.high : Priority.defaultPriority,
            groupKey: groupKey,
            styleInformation: BigTextStyleInformation(body),
            category: AndroidNotificationCategory.status,
          ),
        ),
      );
    } catch (_) {
      // Ignorar fallos al mostrar.
    }
  }
}
