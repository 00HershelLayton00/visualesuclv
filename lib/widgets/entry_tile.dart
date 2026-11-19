import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/media_types.dart';
import '../models/remote_entry.dart';

/// Fila de un archivo o carpeta en modo lista.
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final RemoteEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = entry.kind;
    final color = colorForKind(kind, scheme);
    final icon = kind == MediaKind.folder
        ? folderIconForName(entry.name)
        : iconForKind(kind);

    final subtitle = entry.isDirectory
        ? formatRelative(entry.modified)
        : '${formatBytes(entry.size)} · ${formatRelative(entry.modified)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
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
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  Icon(Icons.chevron_right_rounded, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de un archivo o carpeta en modo cuadricula.
class EntryGridCard extends StatelessWidget {
  const EntryGridCard({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.badge,
  });

  final RemoteEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = entry.kind;
    final icon = kind == MediaKind.folder
        ? folderIconForName(entry.name)
        : iconForKind(kind);
    final gradient = gradientForKind(kind, scheme);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 23),
                  ),
                  const Spacer(),
                  ?badge,
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.isDirectory
                    ? formatRelative(entry.modified)
                    : formatBytes(entry.size),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
