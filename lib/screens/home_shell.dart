import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../core/url_utils.dart';
import '../globals.dart';
import '../models/remote_entry.dart';
import '../services/download_manager.dart';
import '../services/favorites_service.dart';
import '../services/public_storage.dart';
import 'browser_screen.dart';
import 'downloads_tab.dart';
import 'explore_tab.dart';
import 'favorites_tab.dart';
import 'search_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  final Set<int> _builtTabs = {0};
  late final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
        4,
        (_) => GlobalKey<NavigatorState>(),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pendingNotificationPayload.addListener(_handlePendingPayload);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingPayload();
      _scheduleAutoCheck();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pendingNotificationPayload.removeListener(_handlePendingPayload);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final favorites = context.read<FavoritesService>();
    if (!favorites.isChecking) {
      favorites.reload();
    }
    _scheduleAutoCheck();
  }

  void _scheduleAutoCheck() {
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (!mounted) return;
      final favorites = context.read<FavoritesService>();
      if (favorites.count == 0 || favorites.isChecking) return;
      final last = favorites.lastCheckAt;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(hours: 6)) {
        favorites.checkAll(notify: true);
      }
    });
  }

  void _handlePendingPayload() {
    final payload = pendingNotificationPayload.value;
    if (payload == null || !mounted) return;
    pendingNotificationPayload.value = null;
    if (payload.startsWith('folder:')) {
      final url = payload.substring('folder:'.length);
      setState(() {
        _builtTabs.add(0);
        _index = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKeys[0].currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => BrowserScreen(
              initial: RemoteEntry(
                name: fileNameOf(url),
                url: url,
                isDirectory: true,
              ),
            ),
          ),
        );
      });
    } else if (payload.startsWith('file:')) {
      OpenFilex.open(payload.substring('file:'.length));
    } else if (payload.startsWith('uri:')) {
      PublicStorage.openUri(payload.substring('uri:'.length));
    }
  }

  Future<void> _handleBack() async {
    final navigator = _navigatorKeys[_index].currentState;
    if (navigator != null && await navigator.maybePop()) return;
    await SystemNavigator.pop();
  }

  void _onDestinationSelected(int value) {
    if (value == _index) {
      _navigatorKeys[value].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _builtTabs.add(value);
      _index = value;
    });
  }

  Widget _rootFor(int index) {
    switch (index) {
      case 0:
        return ExploreTab(
          onOpenSearch: () => _onDestinationSelected(1),
          onOpenTab: _onDestinationSelected,
        );
      case 1:
        return const SearchTab();
      case 2:
        return const FavoritesTab();
      default:
        return const DownloadsTab();
    }
  }

  Widget _tabNavigator(int index) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _rootFor(index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = context.select<FavoritesService, int>(
      (service) => service.unreadCount,
    );
    final activeDownloads = context.select<DownloadManager, int>(
      (service) => service.activeCount,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: bottomBarVisible,
        builder: (context, barVisible, _) => Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              for (var tab = 0; tab < 4; tab++)
                _builtTabs.contains(tab)
                    ? _tabNavigator(tab)
                    : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: barVisible
              ? NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _onDestinationSelected,
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Inicio',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.search_rounded),
                      selectedIcon: Icon(Icons.manage_search_rounded),
                      label: 'Buscar',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: unreadCount > 0,
                        label: Text('$unreadCount'),
                        child: const Icon(Icons.star_border_rounded),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: unreadCount > 0,
                        label: Text('$unreadCount'),
                        child: const Icon(Icons.star_rounded),
                      ),
                      label: 'Favoritos',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: activeDownloads > 0,
                        label: Text('$activeDownloads'),
                        child: const Icon(Icons.download_outlined),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: activeDownloads > 0,
                        label: Text('$activeDownloads'),
                        child: const Icon(Icons.download_rounded),
                      ),
                      label: 'Descargas',
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}
