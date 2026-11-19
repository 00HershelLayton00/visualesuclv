import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/contact.dart';
import '../core/formatters.dart';
import '../globals.dart';
import '../models/remote_entry.dart';
import '../services/directory_service.dart';
import '../services/download_manager.dart';
import '../services/favorites_service.dart';
import '../services/search_index_service.dart';
import '../theme.dart';
import '../widgets/entry_tile.dart';
import '../widgets/status_views.dart';
import 'browser_screen.dart';
import 'settings_screen.dart';

class ExploreTab extends StatefulWidget {
  const ExploreTab({super.key, required this.onOpenSearch, this.onOpenTab});

  final VoidCallback onOpenSearch;
  final ValueChanged<int>? onOpenTab;

  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  List<RemoteEntry>? _entries;
  bool _loading = true;
  bool _offline = false;
  String? _error;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final directories = context.read<DirectoryService>();
    final api = context.read<ApiClient>();
    final rootUrl = '${api.baseUrl}/';
    final token = ++_loadToken;

    final cached = await directories.cachedAsync(rootUrl);
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
      final entries = await directories.list(rootUrl, force: true);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _offline = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted || token != _loadToken) return;
      final fallback = cached ?? directories.cached(rootUrl);
      setState(() {
        _loading = false;
        _error = error.message;
        _offline = fallback != null && fallback.isNotEmpty;
        if (fallback != null && fallback.isNotEmpty) {
          _entries = fallback;
        }
      });
    }
  }

  void _open(RemoteEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => BrowserScreen(initial: entry)),
    );
  }

  void _openRecent() {
    final api = context.read<ApiClient>();
    final entries = _entries ?? const <RemoteEntry>[];
    for (final entry in entries) {
      if (entry.isDirectory && foldText(entry.name) == 'recientes') {
        _open(entry);
        return;
      }
    }
    _open(
      RemoteEntry(
        name: 'Recientes',
        url: '${api.baseUrl}/Recientes/',
        isDirectory: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final indexedCount = context.select<SearchIndexService, int>(
      (service) => service.entryCount,
    );
    final favoriteCount = context.select<FavoritesService, int>(
      (service) => service.count,
    );
    final activeDownloads = context.select<DownloadManager, int>(
      (service) => service.activeCount,
    );

    final entries = _entries ?? const <RemoteEntry>[];
    final folders = [
      for (final entry in entries)
        if (entry.isDirectory) entry,
    ];
    final files = [
      for (final entry in entries)
        if (!entry.isDirectory) entry,
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              title: const Text(appName),
              actions: [
                IconButton(
                  tooltip: 'Ajustes',
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverToBoxAdapter(
              child: _HeroCard(
                folderCount: indexedCount,
                favoriteCount: favoriteCount,
                activeDownloads: activeDownloads,
                gradient: heroGradient(scheme),
              ),
            ),
            SliverToBoxAdapter(
              child: _SearchBanner(onTap: widget.onOpenSearch),
            ),
            const SliverToBoxAdapter(child: _ContactCard()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    const Text(
                      'Accesos rapidos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _QuickChip(
                      icon: Icons.new_releases_rounded,
                      label: 'Recientes',
                      onTap: _openRecent,
                    ),
                    _QuickChip(
                      icon: Icons.search_rounded,
                      label: 'Buscar todo',
                      onTap: widget.onOpenSearch,
                    ),
                    _QuickChip(
                      icon: Icons.star_rounded,
                      label: 'Favoritos ($favoriteCount)',
                      onTap: () => widget.onOpenTab?.call(2),
                    ),
                    _QuickChip(
                      icon: Icons.download_rounded,
                      label: 'Descargas ($activeDownloads)',
                      onTap: () => widget.onOpenTab?.call(3),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading && _entries == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: LoadingView(
                    message: 'Conectando con visuales.uclv.cu',
                  ),
                ),
              )
            else if (_error != null && _entries == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: ErrorView(message: _error!, onRetry: _load),
                ),
              )
            else ...[
              if (_offline && _error != null)
                SliverToBoxAdapter(
                  child: WarningBanner(
                    message: 'Sin conexion. Mostrando el contenido guardado.',
                  ),
                ),
              SliverToBoxAdapter(
                child: const _SectionHeader(title: 'Categorias'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 172,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: folders.length,
                  itemBuilder: (context, position) {
                    final folder = folders[position];
                    return EntryGridCard(
                      entry: folder,
                      onTap: () => _open(folder),
                      onLongPress: () => _open(folder),
                    );
                  },
                ),
              ),
              if (files.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: const _SectionHeader(title: 'Archivos del inicio'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList.builder(
                    itemCount: files.length,
                    itemBuilder: (context, position) {
                      final file = files[position];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: EntryTile(
                            entry: file,
                            onTap: () => _open(file),
                            onLongPress: () => _open(file),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.folderCount,
    required this.favoriteCount,
    required this.activeDownloads,
    required this.gradient,
  });

  final int folderCount;
  final int favoriteCount;
  final int activeDownloads;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.movie_filter_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appTagline,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _HeroStat(
                value: folderCount > 0 ? formatCount(folderCount) : '—',
                label: 'carpetas',
              ),
              _HeroStat(value: '$favoriteCount', label: 'favoritos'),
              _HeroStat(value: '$activeDownloads', label: 'descargas'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBanner extends StatelessWidget {
  const _SearchBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.travel_explore_rounded, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Buscar en todo el sitio...',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openEngineerContact(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Donaciones y peticiones',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Escribele al ingeniero por WhatsApp',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: scheme.primary),
        label: Text(label),
        onPressed: onTap,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        backgroundColor: scheme.surface,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}
