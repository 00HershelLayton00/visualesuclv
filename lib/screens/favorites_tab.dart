import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/media_types.dart';
import '../models/change_event.dart';
import '../models/favorite_folder.dart';
import '../models/remote_entry.dart';
import '../services/favorites_service.dart';
import '../widgets/status_views.dart';
import 'browser_screen.dart';

enum _FavoriteAction { open, check, remove }

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  void _open(BuildContext context, String url, String name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowserScreen(
          initial: RemoteEntry(name: name, url: url, isDirectory: true),
        ),
      ),
    );
  }

  Future<void> _checkAll(BuildContext context) async {
    final favorites = context.read<FavoritesService>();
    final messenger = ScaffoldMessenger.of(context);
    final summary = await favorites.checkAll(notify: true);
    messenger.showSnackBar(SnackBar(content: Text(summary.message)));
  }

  Future<void> _checkOne(BuildContext context, FavoriteFolder favorite) async {
    final favorites = context.read<FavoritesService>();
    final messenger = ScaffoldMessenger.of(context);
    final summary = await favorites.checkOne(favorite.url, notify: true);
    messenger.showSnackBar(SnackBar(content: Text(summary.message)));
  }

  Future<void> _remove(BuildContext context, FavoriteFolder favorite) async {
    final favorites = context.read<FavoritesService>();
    final messenger = ScaffoldMessenger.of(context);
    await favorites.remove(favorite.url);
    messenger.showSnackBar(
      SnackBar(content: Text('"${favorite.name}" ya no esta en favoritos.')),
    );
  }

  Future<void> _clearEvents(BuildContext context) async {
    final favorites = context.read<FavoritesService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar novedades'),
        content: const Text('Se ocultara el historial de cambios detectados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await favorites.clearEvents();
  }

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesService>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoritos'),
        actions: [
          if (favorites.events.isNotEmpty)
            IconButton(
              tooltip: 'Marcar novedades como leidas',
              onPressed: favorites.markEventsRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
          if (favorites.events.isNotEmpty)
            IconButton(
              tooltip: 'Borrar novedades',
              onPressed: () => _clearEvents(context),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          IconButton(
            tooltip: 'Buscar cambios ahora',
            onPressed: favorites.isChecking || favorites.count == 0
                ? null
                : () => _checkAll(context),
            icon: favorites.isChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _checkAll(context),
        child: favorites.count == 0 && favorites.events.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: const EmptyView(
                      title: 'Sin carpetas favoritas',
                      message:
                          'Abre una carpeta y toca la estrella para '
                          'recibir avisos cuando cambie o desaparezca.',
                      icon: Icons.star_border_rounded,
                    ),
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                children: [
                  if (favorites.isChecking)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  if (favorites.events.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          'Novedades',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (favorites.unreadCount > 0)
                          Badge(label: Text('${favorites.unreadCount}')),
                        const Spacer(),
                        if (favorites.lastCheckAt != null)
                          Text(
                            'Revisado ${formatRelative(favorites.lastCheckAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final event in favorites.events.take(15))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _EventCard(
                          event: event,
                          onTap: () {
                            favorites.markEventRead(event);
                            _open(context, event.folderUrl, event.folderName);
                          },
                        ),
                      ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Text(
                        'Carpetas',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${favorites.count}',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final favorite in favorites.favorites)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FavoriteCard(
                        favorite: favorite,
                        hasUnread: favorites.hasUnreadEventFor(favorite.url),
                        onTap: () =>
                            _open(context, favorite.url, favorite.name),
                        onAction: (action) async {
                          switch (action) {
                            case _FavoriteAction.open:
                              _open(context, favorite.url, favorite.name);
                            case _FavoriteAction.check:
                              await _checkOne(context, favorite);
                            case _FavoriteAction.remove:
                              await _remove(context, favorite);
                          }
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.favorite,
    required this.hasUnread,
    required this.onTap,
    required this.onAction,
  });

  final FavoriteFolder favorite;
  final bool hasUnread;
  final VoidCallback onTap;
  final ValueChanged<_FavoriteAction> onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _statusText(favorite);
    final statusColor = favorite.missing
        ? scheme.error
        : favorite.lastError != null
        ? scheme.tertiary
        : scheme.onSurfaceVariant;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: favorite.missing
                          ? scheme.errorContainer.withValues(alpha: 0.5)
                          : scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      favorite.missing
                          ? Icons.folder_off_rounded
                          : folderIconForName(favorite.name),
                      color: favorite.missing ? scheme.error : scheme.primary,
                      size: 25,
                    ),
                  ),
                  if (hasUnread)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: scheme.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      favorite.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      favorite.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight:
                            favorite.missing || favorite.lastError != null
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_FavoriteAction>(
                tooltip: 'Opciones',
                onSelected: onAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _FavoriteAction.open,
                    child: Text('Abrir carpeta'),
                  ),
                  PopupMenuItem(
                    value: _FavoriteAction.check,
                    child: Text('Buscar cambios'),
                  ),
                  PopupMenuItem(
                    value: _FavoriteAction.remove,
                    child: Text('Quitar de favoritos'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(FavoriteFolder favorite) {
    if (favorite.missing) {
      return 'Desaparecio del sitio · revisado '
          '${formatRelative(favorite.lastChecked)}';
    }
    if (favorite.lastError != null) {
      return '${favorite.lastError} · ${formatRelative(favorite.lastChecked)}';
    }
    final items = favorite.snapshot.length;
    return '$items elemento${items == 1 ? '' : 's'} · revisado '
        '${formatRelative(favorite.lastChecked)}';
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final ChangeEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (event.type) {
      ChangeEventType.updated => (Icons.auto_awesome_rounded, scheme.primary),
      ChangeEventType.disappeared => (
        Icons.report_gmailerrorred_rounded,
        scheme.error,
      ),
      ChangeEventType.restored => (
        Icons.restore_rounded,
        const Color(0xFF2E7D32),
      ),
    };
    final unread = !event.read;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.folderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          FavoritesService.describeEvent(event),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatRelative(event.at),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (event.hasItems) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in event.added.take(3))
                      _ItemPill(text: '+ $name', color: scheme.primary),
                    for (final name in event.removed.take(2))
                      _ItemPill(text: '- $name', color: scheme.error),
                    if (event.totalAdded > 3)
                      _ItemPill(
                        text: '+${event.totalAdded - 3} mas',
                        color: scheme.primary,
                      ),
                    if (event.totalRemoved > 2)
                      _ItemPill(
                        text: '-${event.totalRemoved - 2} mas',
                        color: scheme.error,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemPill extends StatelessWidget {
  const _ItemPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
