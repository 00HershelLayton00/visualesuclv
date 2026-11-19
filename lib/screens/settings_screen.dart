import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/contact.dart';
import '../core/formatters.dart';
import '../globals.dart';
import '../services/directory_service.dart';
import '../services/download_manager.dart';
import '../services/favorites_service.dart';
import '../services/notification_service.dart';
import '../services/search_index_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _checkNow(BuildContext context) async {
    final favorites = context.read<FavoritesService>();
    final messenger = ScaffoldMessenger.of(context);
    final summary = await favorites.checkAll(notify: true);
    messenger.showSnackBar(SnackBar(content: Text(summary.message)));
  }

  Future<void> _requestNotifications(BuildContext context) async {
    final notifications = context.read<NotificationService>();
    final messenger = ScaffoldMessenger.of(context);
    await notifications.requestPermission();
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Puedes gestionar los permisos desde los ajustes de Android.',
        ),
      ),
    );
  }

  Future<void> _testConnection(BuildContext context) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final stopwatch = Stopwatch()..start();
    try {
      await api.getText(api.baseUrl, timeout: const Duration(seconds: 20));
      stopwatch.stop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Conexion correcta en ${stopwatch.elapsedMilliseconds} ms '
            '(${api.scheme.toUpperCase()}).',
          ),
        ),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _refreshIndex(BuildContext context) async {
    final index = context.read<SearchIndexService>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await index.refresh();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Indice actualizado: ${formatCount(index.entryCount)} carpetas.'
              : index.error ?? 'No se pudo actualizar el indice.',
        ),
      ),
    );
  }

  Future<void> _rebuildIndex(BuildContext context) async {
    final index = context.read<SearchIndexService>();
    final messenger = ScaffoldMessenger.of(context);
    await index.clearAndRefresh();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Indice reconstruido: ${formatCount(index.entryCount)} carpetas.',
        ),
      ),
    );
  }

  Future<void> _clearFolderCache(BuildContext context) async {
    final directories = context.read<DirectoryService>();
    final messenger = ScaffoldMessenger.of(context);
    await directories.clearCache();
    messenger.showSnackBar(
      const SnackBar(content: Text('Cache de navegacion borrada.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsService>();
    final index = context.watch<SearchIndexService>();
    final favorites = context.watch<FavoritesService>();
    final downloads = context.watch<DownloadManager>();
    final api = context.read<ApiClient>();

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _SectionTitle(title: 'Apariencia'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Sistema'),
                    icon: Icon(Icons.brightness_auto_rounded),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Claro'),
                    icon: Icon(Icons.light_mode_rounded),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Oscuro'),
                    icon: Icon(Icons.dark_mode_rounded),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (selection) =>
                    settings.setThemeMode(selection.first),
              ),
            ),
          ),
          _SectionTitle(title: 'Avisos de carpetas favoritas'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Comprobar en segundo plano'),
                  subtitle: const Text(
                    'Revisa tus carpetas cada 30 minutos y avisa de cambios',
                  ),
                  value: settings.backgroundChecks,
                  onChanged: (value) => settings.setBackgroundChecks(value),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Buscar cambios ahora'),
                  subtitle: Text(
                    favorites.lastCheckAt != null
                        ? 'Ultima revision '
                              '${formatRelative(favorites.lastCheckAt)}'
                        : 'Aun no se ha revisado ninguna carpeta',
                  ),
                  trailing: favorites.isChecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.sync_rounded),
                  onTap: favorites.isChecking || favorites.count == 0
                      ? null
                      : () => _checkNow(context),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Permitir notificaciones'),
                  subtitle: const Text(
                    'Necesario para recibir los avisos de cambios',
                  ),
                  trailing: const Icon(Icons.notifications_active_outlined),
                  onTap: () => _requestNotifications(context),
                ),
              ],
            ),
          ),
          _SectionTitle(title: 'Busqueda global'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Carpetas indexadas'),
                  trailing: Text(
                    formatCount(index.entryCount),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Ultima actualizacion'),
                  trailing: Text(
                    index.updatedAt != null
                        ? formatRelative(index.updatedAt)
                        : 'Nunca',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Actualizar indice'),
                  subtitle: const Text('Descarga unos 4,4 MB'),
                  trailing: index.isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  onTap: index.isBusy ? null : () => _refreshIndex(context),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Reconstruir indice'),
                  subtitle: const Text(
                    'Borra la copia local y la descarga otra vez',
                  ),
                  trailing: const Icon(Icons.autorenew_rounded),
                  onTap: index.isBusy ? null : () => _rebuildIndex(context),
                ),
              ],
            ),
          ),
          _SectionTitle(title: 'Servidor'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Direccion'),
                  subtitle: Text(
                    '${api.baseUrl}/ (${api.scheme.toUpperCase()})',
                  ),
                  trailing: const Icon(Icons.dns_rounded),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Probar conexion'),
                  trailing: const Icon(Icons.network_check_rounded),
                  onTap: () => _testConnection(context),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    'visuales.uclv.cu solo esta disponible desde la red de '
                    'Cuba. Si estas fuera, las descargas y la busqueda no '
                    'funcionaran aunque la app abra.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SectionTitle(title: 'Almacenamiento'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Carpeta de descargas'),
                  subtitle: Text(downloads.storageLabel),
                  trailing: const Icon(Icons.folder_rounded),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Descargas en curso'),
                  trailing: Text(
                    '${downloads.activeCount}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Borrar cache de navegacion'),
                  subtitle: const Text(
                    'Libera espacio de las carpetas guardadas',
                  ),
                  trailing: const Icon(Icons.cleaning_services_outlined),
                  onTap: () => _clearFolderCache(context),
                ),
              ],
            ),
          ),
          _SectionTitle(title: 'Contacto'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF25D366),
                    child: Icon(
                      Icons.support_agent_rounded,
                      color: Colors.white,
                    ),
                  ),
                  title: const Text('Donaciones y peticiones'),
                  subtitle: const Text('Escribele al ingeniero por WhatsApp'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => openEngineerContact(context),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      contactUrl,
                      style: TextStyle(fontSize: 12, color: scheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SectionTitle(title: 'Acerca de'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(0xFF5B4DD6),
                    child: Icon(
                      Icons.movie_filter_rounded,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(appName),
                  subtitle: Text('Version $appVersion'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    '$appTagline. Navega, busca, descarga y guarda carpetas '
                    'favoritas con avisos de cambios. Hecho para la red de Cuba.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
