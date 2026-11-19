import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/media_types.dart';
import '../core/url_utils.dart';
import '../models/download_task.dart';
import '../models/remote_entry.dart';
import '../services/directory_service.dart';
import '../services/download_manager.dart';
import '../services/favorites_service.dart';
import '../widgets/entry_tile.dart';
import '../widgets/status_views.dart';
import 'player_screen.dart';

enum _SortMode { name, newest, size }

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.initial});

  final RemoteEntry initial;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late String _url;
  late String _name;
  List<RemoteEntry>? _entries;
  bool _loading = true;
  bool _offline = false;
  String? _error;
  _SortMode _sort = _SortMode.name;
  bool _grid = false;
  bool _filterVisible = false;
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _url = canonicalFolderUrl(widget.initial.url);
    _name = widget.initial.name;
    _load();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final directories = context.read<DirectoryService>();
    final token = ++_loadToken;
    final url = _url;

    final cached = await directories.cachedAsync(url);
    if (!mounted || token != _loadToken) return;
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _entries = cached;
        _loading = false;
        _error = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final entries = await directories.list(url, force: true);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _offline = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted || token != _loadToken) return;
      final fallback = cached ?? directories.cached(url);
      setState(() {
        _loading = false;
        _error = error.message;
        _offline = fallback != null && fallback.isNotEmpty;
        _entries = fallback != null && fallback.isNotEmpty ? fallback : null;
      });
    }
  }

  void _goTo(String url, String name) {
    setState(() {
      _url = canonicalFolderUrl(url);
      _name = name;
      _filter = '';
      _filterController.clear();
    });
    _load();
  }

  void _openEntry(RemoteEntry entry) {
    if (entry.isDirectory) {
      _goTo(entry.url, entry.name);
    } else {
      _showEntrySheet(entry);
    }
  }

  Future<void> _toggleFavorite(RemoteEntry entry, {bool silent = false}) async {
    final favorites = context.read<FavoritesService>();
    final isFavorite = await favorites.toggle(
      entry.url,
      entry.isDirectory ? entry.name : displayPathOf(entry.url),
    );
    if (!mounted || silent) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isFavorite
              ? 'Guardado en favoritos. Te avisaremos si cambia.'
              : 'Eliminado de favoritos.',
        ),
      ),
    );
  }

  Future<void> _download(RemoteEntry entry) async {
    final downloads = context.read<DownloadManager>();
    final existing = downloads.taskForUrl(entry.url);
    if (existing != null && existing.status == DownloadStatus.completed) {
      final opened = await downloads.open(existing);
      if (!mounted) return;
      if (!opened) {
        _showMessage('No se pudo abrir el archivo.');
      }
      return;
    }
    if (existing != null && existing.isActive) {
      _showMessage('La descarga ya esta en curso.');
      return;
    }
    try {
      await downloads.start(entry);
      if (!mounted) return;
      _showMessage('Descarga iniciada: ${entry.name}');
    } catch (error) {
      if (!mounted) return;
      _showMessage('No se pudo iniciar la descarga: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showEntrySheet(RemoteEntry entry) {
    final kind = entry.kind;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final color = colorForKind(kind, scheme);
        final icon = entry.isDirectory
            ? folderIconForName(entry.name)
            : iconForKind(kind);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: color, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            entry.isDirectory
                                ? 'Carpeta · ${formatRelative(entry.modified)}'
                                : '${formatBytes(entry.size)} · '
                                      '${formatRelative(entry.modified)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (!entry.isDirectory && canPlayInApp(kind))
                  _SheetAction(
                    icon: kind == MediaKind.image
                        ? Icons.visibility_rounded
                        : Icons.play_circle_fill_rounded,
                    label: kind == MediaKind.image
                        ? 'Ver imagen'
                        : 'Reproducir',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlayerScreen(entry: entry),
                        ),
                      );
                    },
                  ),
                if (!entry.isDirectory)
                  Consumer<DownloadManager>(
                    builder: (context, downloads, _) {
                      final task = downloads.taskForUrl(entry.url);
                      if (task == null) {
                        return _SheetAction(
                          icon: Icons.download_rounded,
                          label: 'Descargar',
                          subtitle: formatBytes(entry.size),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _download(entry);
                          },
                        );
                      }
                      switch (task.status) {
                        case DownloadStatus.completed:
                          return _SheetAction(
                            icon: Icons.play_arrow_rounded,
                            label: 'Abrir descarga',
                            subtitle: 'Completada',
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              final opened = await downloads.open(task);
                              if (!mounted) return;
                              if (!opened) {
                                _showMessage('No se pudo abrir el archivo.');
                              }
                            },
                          );
                        case DownloadStatus.downloading:
                        case DownloadStatus.queued:
                          return _SheetAction(
                            icon: Icons.pause_rounded,
                            label: 'Pausar descarga',
                            subtitle:
                                '${(task.progress * 100).toStringAsFixed(0)} %',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              downloads.pause(task);
                            },
                          );
                        case DownloadStatus.paused:
                          return _SheetAction(
                            icon: Icons.play_arrow_rounded,
                            label: 'Reanudar descarga',
                            subtitle:
                                '${(task.progress * 100).toStringAsFixed(0)} %',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              downloads.resume(task);
                            },
                          );
                        case DownloadStatus.failed:
                          return _SheetAction(
                            icon: Icons.refresh_rounded,
                            label: 'Reintentar descarga',
                            subtitle: task.error,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              downloads.resume(task);
                            },
                          );
                        case DownloadStatus.canceled:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                if (entry.isDirectory)
                  Consumer<FavoritesService>(
                    builder: (context, favorites, _) {
                      final isFavorite = favorites.isFavorite(entry.url);
                      return _SheetAction(
                        icon: isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        label: isFavorite
                            ? 'Quitar de favoritos'
                            : 'Anadir a favoritos',
                        subtitle: isFavorite
                            ? 'Recibes avisos de cambios'
                            : 'Avisos cuando cambie o desaparezca',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _toggleFavorite(entry);
                        },
                      );
                    },
                  ),
                _SheetAction(
                  icon: Icons.link_rounded,
                  label: 'Copiar enlace',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await Clipboard.setData(ClipboardData(text: entry.url));
                    if (!mounted) return;
                    _showMessage('Enlace copiado.');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<RemoteEntry> get _visibleEntries {
    var entries = _entries ?? const <RemoteEntry>[];
    final query = foldText(_filter.trim());
    if (query.isNotEmpty) {
      entries = [
        for (final entry in entries)
          if (foldText(entry.name).contains(query)) entry,
      ];
    }
    final sorted = List<RemoteEntry>.of(entries);
    sorted.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (_sort) {
        case _SortMode.name:
          return foldText(a.name).compareTo(foldText(b.name));
        case _SortMode.newest:
          final aDate = a.modified?.millisecondsSinceEpoch ?? 0;
          final bDate = b.modified?.millisecondsSinceEpoch ?? 0;
          return bDate.compareTo(aDate);
        case _SortMode.size:
          return (b.size ?? -1).compareTo(a.size ?? -1);
      }
    });
    return sorted;
  }

  List<(String, String)> get _crumbs {
    final uri = Uri.parse(_url);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final crumbs = <(String, String)>[];
    var path = '';
    for (final segment in segments) {
      path += '/${Uri.encodeComponent(segment)}';
      crumbs.add((segment, '${uri.scheme}://${uri.authority}$path/'));
    }
    return crumbs;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final favorites = context.watch<FavoritesService>();
    final isFavorite = favorites.isFavorite(_url);
    final entries = _visibleEntries;
    final folderCount = entries.where((entry) => entry.isDirectory).length;
    final fileCount = entries.length - folderCount;
    final isRoot = parentUrlOf(_url) == null;

    return PopScope(
      canPop: isRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final parent = parentUrlOf(_url);
        if (parent != null) _goTo(parent, fileNameOf(parent));
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              if (_crumbs.length > 1)
                Text(
                  _crumbs.take(_crumbs.length - 1).map((c) => c.$1).join(' / '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: isFavorite
                  ? 'Quitar de favoritos'
                  : 'Anadir a favoritos',
              onPressed: () => _toggleFavorite(
                RemoteEntry(name: _name, url: _url, isDirectory: true),
              ),
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: isFavorite ? const Color(0xFFFFB300) : null,
              ),
            ),
            IconButton(
              tooltip: 'Filtrar en esta carpeta',
              onPressed: () => setState(() {
                _filterVisible = !_filterVisible;
                if (!_filterVisible) {
                  _filter = '';
                  _filterController.clear();
                }
              }),
              icon: Icon(
                _filterVisible ? Icons.filter_alt : Icons.filter_alt_outlined,
              ),
            ),
            PopupMenuButton<_SortMode>(
              tooltip: 'Ordenar',
              initialValue: _sort,
              onSelected: (mode) => setState(() => _sort = mode),
              itemBuilder: (context) => const [
                PopupMenuItem(value: _SortMode.name, child: Text('Nombre')),
                PopupMenuItem(
                  value: _SortMode.newest,
                  child: Text('Mas recientes'),
                ),
                PopupMenuItem(value: _SortMode.size, child: Text('Tamano')),
              ],
              icon: const Icon(Icons.sort_rounded),
            ),
            IconButton(
              tooltip: _grid ? 'Ver en lista' : 'Ver en cuadricula',
              onPressed: () => setState(() => _grid = !_grid),
              icon: Icon(
                _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _buildBody(entries, folderCount, fileCount),
      ),
    );
  }

  Widget _buildBody(List<RemoteEntry> entries, int folderCount, int fileCount) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading && _entries == null) {
      return const LoadingView(message: 'Cargando contenido...');
    }
    if (_error != null && _entries == null) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    final downloads = context.watch<DownloadManager>();
    final favorites = context.watch<FavoritesService>();

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildCrumbs(scheme)),
          if (_offline && _error != null)
            SliverToBoxAdapter(
              child: WarningBanner(
                message: 'Mostrando contenido guardado. $_error',
              ),
            ),
          if (_filterVisible)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  controller: _filterController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _filter = value),
                  decoration: InputDecoration(
                    hintText: 'Filtrar en $_name',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _filter.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _filter = '';
                              _filterController.clear();
                            }),
                          ),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Row(
                children: [
                  Text(
                    '$folderCount carpeta${folderCount == 1 ? '' : 's'}'
                    '${fileCount > 0 ? ' · $fileCount archivo${fileCount == 1 ? '' : 's'}' : ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyView(
                title: _filter.isNotEmpty
                    ? 'Sin coincidencias'
                    : 'Carpeta vacia',
                message: _filter.isNotEmpty
                    ? 'Ningun elemento contiene "$_filter".'
                    : 'Aqui no hay archivos disponibles.',
                icon: Icons.folder_off_rounded,
              ),
            )
          else if (_grid)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 172,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return EntryGridCard(
                    entry: entry,
                    onTap: () => _openEntry(entry),
                    onLongPress: () => _showEntrySheet(entry),
                    badge: entry.isDirectory
                        ? null
                        : _buildDownloadBadge(entry, downloads),
                  );
                },
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: EntryTile(
                        entry: entry,
                        onTap: () => _openEntry(entry),
                        onLongPress: () => _showEntrySheet(entry),
                        trailing: entry.isDirectory
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (favorites.isFavorite(entry.url))
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 18,
                                      color: Color(0xFFFFB300),
                                    ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: scheme.outline,
                                  ),
                                ],
                              )
                            : _buildDownloadTrailing(entry, downloads),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCrumbs(ColorScheme scheme) {
    final crumbs = _crumbs;
    if (crumbs.length <= 1) return const SizedBox(height: 4);
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: crumbs.length,
        separatorBuilder: (_, _) =>
            Icon(Icons.chevron_right_rounded, size: 16, color: scheme.outline),
        itemBuilder: (context, index) {
          final crumb = crumbs[index];
          final isLast = index == crumbs.length - 1;
          return Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: isLast ? null : () => _goTo(crumb.$2, crumb.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isLast
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  crumb.$1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                    color: isLast
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDownloadTrailing(RemoteEntry entry, DownloadManager downloads) {
    final task = downloads.taskForUrl(entry.url);
    if (task == null) {
      return IconButton(
        tooltip: 'Descargar',
        onPressed: () => _download(entry),
        icon: const Icon(Icons.download_rounded),
      );
    }
    switch (task.status) {
      case DownloadStatus.completed:
        return IconButton(
          tooltip: 'Abrir',
          onPressed: () async {
            final opened = await downloads.open(task);
            if (!mounted) return;
            if (!opened) {
              _showMessage('No se pudo abrir el archivo.');
            }
          },
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF2E7D32),
          ),
        );
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        return IconButton(
          tooltip: 'Pausar',
          onPressed: () => downloads.pause(task),
          icon: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              value: task.progress == 0 ? null : task.progress,
              strokeWidth: 2.6,
            ),
          ),
        );
      case DownloadStatus.paused:
        return IconButton(
          tooltip: 'Reanudar',
          onPressed: () => downloads.resume(task),
          icon: const Icon(Icons.play_circle_outline_rounded),
        );
      case DownloadStatus.failed:
        return IconButton(
          tooltip: 'Reintentar',
          onPressed: () => downloads.resume(task),
          icon: Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
        );
      case DownloadStatus.canceled:
        return IconButton(
          tooltip: 'Descargar',
          onPressed: () => _download(entry),
          icon: const Icon(Icons.download_rounded),
        );
    }
  }

  Widget _buildDownloadBadge(RemoteEntry entry, DownloadManager downloads) {
    final task = downloads.taskForUrl(entry.url);
    if (task == null) return const SizedBox.shrink();
    switch (task.status) {
      case DownloadStatus.completed:
        return const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF2E7D32),
          size: 20,
        );
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: task.progress == 0 ? null : task.progress,
            strokeWidth: 2.4,
          ),
        );
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle_outline_rounded, size: 20);
      case DownloadStatus.failed:
        return const Icon(Icons.error_outline_rounded, size: 20);
      case DownloadStatus.canceled:
        return const SizedBox.shrink();
    }
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: scheme.primary, size: 21),
      ),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
