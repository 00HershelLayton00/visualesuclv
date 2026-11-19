import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/media_types.dart';
import '../models/download_task.dart';
import '../services/download_manager.dart';
import '../widgets/status_views.dart';

class DownloadsTab extends StatelessWidget {
  const DownloadsTab({super.key});

  Future<void> _open(BuildContext context, DownloadTask task) async {
    final downloads = context.read<DownloadManager>();
    final messenger = ScaffoldMessenger.of(context);
    final opened = await downloads.open(task);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el archivo.')),
      );
    }
  }

  Future<void> _clearFinished(BuildContext context) async {
    final downloads = context.read<DownloadManager>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Limpiar descargas'),
        content: const Text(
          'Se eliminaran de la lista y del almacenamiento las descargas '
          'terminadas o fallidas. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await downloads.clearFinished();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadManager>();
    final scheme = Theme.of(context).colorScheme;
    final active = downloads.active;
    final finished = downloads.finished;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Descargas'),
        actions: [
          if (finished.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar terminadas',
              onPressed: () => _clearFinished(context),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: downloads.tasks.isEmpty
          ? const EmptyView(
              title: 'Sin descargas',
              message:
                  'Descarga peliculas, series o musica desde cualquier '
                  'carpeta. Podras pausar y reanudar cuando quieras.',
              icon: Icons.download_rounded,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (active.isNotEmpty) ...[
                  Text(
                    'En curso',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'La descarga continua aunque salgas de la app.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final task in active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ActiveCard(task: task),
                    ),
                  const SizedBox(height: 14),
                ],
                if (finished.isNotEmpty) ...[
                  Text(
                    'Terminadas',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final task in finished)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FinishedCard(
                        task: task,
                        onOpen: () => _open(context, task),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Los archivos se guardan en ${downloads.storageLabel}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final downloads = context.read<DownloadManager>();
    final scheme = Theme.of(context).colorScheme;
    final kind = kindForName(task.fileName);
    final color = colorForKind(kind, scheme);
    final isDownloading = task.status == DownloadStatus.downloading;
    final isFailed = task.status == DownloadStatus.failed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(iconForKind(kind), color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusLabel(task),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isFailed
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: isDownloading ? 'Pausar' : 'Reanudar',
                  onPressed: () => isDownloading
                      ? downloads.pause(task)
                      : downloads.resume(task),
                  icon: Icon(
                    isDownloading
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    size: 28,
                  ),
                ),
                IconButton(
                  tooltip: 'Cancelar',
                  onPressed: () => downloads.remove(task),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: task.progress == 0 ? null : task.progress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  task.total > 0
                      ? '${formatBytes(task.received)} / ${formatBytes(task.total)}'
                      : formatBytes(task.received),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (isDownloading && task.speed > 0)
                  Text(
                    formatSpeed(task.speed),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.queued:
        return 'En cola...';
      case DownloadStatus.downloading:
        return task.total > 0
            ? '${(task.progress * 100).toStringAsFixed(0)} % descargado'
            : 'Descargando...';
      case DownloadStatus.paused:
        return 'En pausa';
      case DownloadStatus.failed:
        return task.error ?? 'Error de descarga';
      case DownloadStatus.completed:
      case DownloadStatus.canceled:
        return '';
    }
  }
}

class _FinishedCard extends StatelessWidget {
  const _FinishedCard({required this.task, required this.onOpen});

  final DownloadTask task;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final downloads = context.read<DownloadManager>();
    final scheme = Theme.of(context).colorScheme;
    final completed = task.status == DownloadStatus.completed;
    final kind = kindForName(task.fileName);
    final color = colorForKind(kind, scheme);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: completed ? onOpen : null,
        onLongPress: completed
            ? null
            : () async {
                final detail = task.error ?? 'Error desconocido';
                await Clipboard.setData(ClipboardData(text: detail));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Detalle del error copiado.')),
                );
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (completed ? color : scheme.error).withValues(
                    alpha: 0.14,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  completed ? iconForKind(kind) : Icons.error_outline_rounded,
                  color: completed ? color : scheme.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      completed
                          ? '${formatBytes(task.received)} · ${formatRelative(task.createdAt)}'
                          : (task.error ?? 'Descarga fallida'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: completed
                            ? scheme.onSurfaceVariant
                            : scheme.error,
                      ),
                    ),
                  ],
                ),
              ),
              if (completed)
                IconButton(
                  tooltip: 'Abrir',
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                )
              else
                IconButton(
                  tooltip: 'Reintentar',
                  onPressed: () => downloads.resume(task),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              IconButton(
                tooltip: 'Eliminar',
                onPressed: () => downloads.remove(task),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
