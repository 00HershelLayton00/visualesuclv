import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/media_types.dart';
import '../models/remote_entry.dart';
import '../models/search_entry.dart';
import '../services/favorites_service.dart';
import '../services/search_index_service.dart';
import '../services/settings_service.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/status_views.dart';
import 'browser_screen.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  static const List<String> _suggestions = [
    'Peliculas',
    'Series',
    'Documentales',
    'Infantiles',
    'Libros',
    'MP3s',
    'Recientes',
  ];

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<SearchEntry> _results = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SearchIndexService>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _results = _query.isEmpty
            ? const []
            : context.read<SearchIndexService>().search(_query);
      });
    });
  }

  void _applyQuery(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    final index = context.read<SearchIndexService>();
    setState(() {
      _query = value.trim();
      _results = index.search(_query);
    });
    context.read<SettingsService>().addRecentSearch(value);
    FocusScope.of(context).unfocus();
  }

  void _openEntry(SearchEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowserScreen(
          initial: RemoteEntry(
            name: entry.name,
            url: entry.url,
            isDirectory: entry.isDirectory,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(SearchEntry entry) async {
    final favorites = context.read<FavoritesService>();
    final added = await favorites.toggle(entry.url, entry.name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? '"${entry.name}" guardada en favoritos.'
              : '"${entry.name}" eliminada de favoritos.',
        ),
      ),
    );
  }

  Future<void> _refreshIndex() async {
    final index = context.read<SearchIndexService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Actualizar indice'),
        content: const Text(
          'Se descargara el listado global del sitio (unos 4,4 MB) para '
          'poder buscar en todas las carpetas. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await index.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Indice actualizado: ${formatCount(index.entryCount)} carpetas.'
              : index.error ?? 'No se pudo actualizar el indice.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = context.watch<SearchIndexService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar'),
        actions: [
          IconButton(
            tooltip: 'Actualizar indice',
            onPressed: index.isBusy ? null : _refreshIndex,
            icon: index.isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  context.read<SettingsService>().addRecentSearch(value);
                }
              },
              decoration: InputDecoration(
                hintText: 'Nombre de pelicula, serie, libro...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _query = '';
                            _results = const [];
                          });
                        },
                      ),
              ),
            ),
          ),
          Expanded(child: _buildBody(index)),
        ],
      ),
    );
  }

  Widget _buildBody(SearchIndexService index) {
    if (index.entryCount == 0 && index.isBusy) {
      return _IndexProgress(index: index);
    }
    if (index.entryCount == 0 && index.status == SearchIndexStatus.error) {
      return ErrorView(
        message: index.error ?? 'No se pudo preparar la busqueda global.',
        onRetry: () => index.refresh(),
      );
    }
    if (index.entryCount == 0) {
      return _IndexIntro(onStart: _refreshIndex);
    }
    if (_query.isEmpty) {
      return _Suggestions(
        suggestions: _suggestions,
        onSelected: _applyQuery,
        index: index,
      );
    }
    if (_results.isEmpty) {
      return EmptyView(
        title: 'Sin resultados',
        message: 'No se encontro ninguna carpeta que coincida con "$_query".',
        icon: Icons.search_off_rounded,
      );
    }
    final favorites = context.watch<FavoritesService>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${formatCount(_results.length)} resultado'
              '${_results.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            itemCount: _results.length,
            itemBuilder: (context, position) {
              final entry = _results[position];
              final isFavorite = favorites.isFavorite(entry.url);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openEntry(entry),
                    onLongPress: entry.isDirectory
                        ? () => _toggleFavorite(entry)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              entry.isDirectory
                                  ? folderIconForName(entry.name)
                                  : Icons.insert_drive_file_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 23,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HighlightedText(
                                  text: entry.name,
                                  query: _query,
                                  maxLines: 1,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  entry.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (entry.isDirectory)
                            IconButton(
                              tooltip: isFavorite
                                  ? 'Quitar de favoritos'
                                  : 'Anadir a favoritos',
                              onPressed: () => _toggleFavorite(entry),
                              icon: Icon(
                                isFavorite
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: isFavorite
                                    ? const Color(0xFFFFB300)
                                    : Theme.of(context).colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _IndexIntro extends StatelessWidget {
  const _IndexIntro({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.travel_explore_rounded,
                size: 42,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Busqueda global',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Para buscar en todas las carpetas del sitio se descarga una '
              'sola vez un indice de unos 4,4 MB. Despues las busquedas son '
              'instantaneas, incluso sin conexion.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Preparar buscador'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onStart,
              child: const Text('Tambien puedes hacerlo desde Ajustes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndexProgress extends StatelessWidget {
  const _IndexProgress({required this.index});

  final SearchIndexService index;

  @override
  Widget build(BuildContext context) {
    final message = switch (index.status) {
      SearchIndexStatus.downloading =>
        'Descargando el listado del sitio (4,4 MB)...',
      SearchIndexStatus.parsing => 'Procesando miles de carpetas...',
      _ => 'Preparando el buscador...',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Solo se hace una vez; despues la busqueda es instantanea.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.suggestions,
    required this.onSelected,
    required this.index,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSelected;
  final SearchIndexService index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsService>();
    final recent = settings.recentSearches;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.travel_explore_rounded, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        index.entryCount > 0
                            ? '${formatCount(index.entryCount)} carpetas indexadas'
                            : 'Indice no disponible',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        index.updatedAt != null
                            ? 'Actualizado ${formatRelative(index.updatedAt)}'
                            : 'Actualiza para buscar en todo el sitio',
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
          ),
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'Busquedas recientes',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => settings.clearRecentSearches(),
                child: const Text('Limpiar'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in recent)
                ActionChip(
                  avatar: const Icon(Icons.history_rounded, size: 16),
                  label: Text(item),
                  onPressed: () => onSelected(item),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Explora por categoria',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in suggestions)
              ActionChip(
                avatar: Icon(folderIconForName(item), size: 16),
                label: Text(item),
                onPressed: () => onSelected(item),
              ),
          ],
        ),
      ],
    );
  }
}
