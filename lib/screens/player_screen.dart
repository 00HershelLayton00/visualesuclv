import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/media_types.dart';
import '../globals.dart';
import '../models/remote_entry.dart';
import '../services/download_manager.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.entry});

  final RemoteEntry entry;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _fullscreen = false;
  String? _error;

  bool get _isImage => widget.entry.kind == MediaKind.image;
  bool get _isAudio => widget.entry.kind == MediaKind.audio;

  @override
  void initState() {
    super.initState();
    if (_isImage) {
      _loading = false;
      return;
    }
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.entry.url),
      httpHeaders: const {'User-Agent': ApiClient.userAgent},
    );
    _controller!
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _loading = false);
          _controller!.play();
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error =
                'No se pudo reproducir este archivo. Puedes descargarlo '
                'y abrirlo con otra aplicacion.';
          });
        });
  }

  @override
  void dispose() {
    _controller?.dispose();
    bottomBarVisible.value = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    bottomBarVisible.value = !next;
    if (next) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  Future<void> _download() async {
    final downloads = context.read<DownloadManager>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await downloads.start(widget.entry);
      messenger.showSnackBar(
        const SnackBar(content: Text('Descarga iniciada.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo iniciar la descarga: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(
                widget.entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
              actions: [
                IconButton(
                  tooltip: 'Descargar',
                  onPressed: _download,
                  icon: const Icon(Icons.download_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isImage) {
      return InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.network(
            widget.entry.url,
            headers: const {'User-Agent': ApiClient.userAgent},
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              final total = progress.expectedTotalBytes;
              return Center(
                child: CircularProgressIndicator(
                  value: total == null
                      ? null
                      : progress.cumulativeBytesLoaded / total,
                ),
              );
            },
            errorBuilder: (context, error, stack) => const Center(
              child: Text(
                'No se pudo cargar la imagen.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white54,
                size: 52,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Descargar archivo'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }

    final controller = _controller!;
    return Column(
      children: [
        if (_isAudio)
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Column(
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C4DFF), Color(0xFF00B3A4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                    size: 54,
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    widget.entry.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        _buildControls(controller),
      ],
    );
  }

  Widget _buildControls(VideoPlayerController controller) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final maxMs = duration.inMilliseconds <= 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final positionMs = value.position.inMilliseconds
            .clamp(0, duration.inMilliseconds)
            .toDouble();
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Colors.black87],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    formatDuration(value.position),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: positionMs,
                      max: maxMs,
                      onChanged: (position) => controller.seekTo(
                        Duration(milliseconds: position.round()),
                      ),
                    ),
                  ),
                  Text(
                    formatDuration(duration),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 6),
                  IconButton(
                    iconSize: 42,
                    onPressed: () => controller.value.isPlaying
                        ? controller.pause()
                        : controller.play(),
                    icon: Icon(
                      value.isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (value.isBuffering)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: _fullscreen
                        ? 'Salir de pantalla completa'
                        : 'Pantalla completa',
                    onPressed: _toggleFullscreen,
                    icon: Icon(
                      _fullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
