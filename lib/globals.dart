import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Payload pendiente de una notificacion tocada por el usuario.
/// Formato: `folder:<url>` o `file:<ruta-local>`.
final ValueNotifier<String?> pendingNotificationPayload = ValueNotifier(null);

/// Oculta la barra inferior (por ejemplo en video a pantalla completa).
final ValueNotifier<bool> bottomBarVisible = ValueNotifier(true);

const String appName = 'Visuales';
const String appTagline = 'Cine, series, musica y libros para Cuba';
const String appVersion = '1.4.0';

/// Contacto del ingeniero para donaciones o peticiones.
const String contactUrl = 'https://wa.me/qr/BY25FVEXLG3JD1';
const String contactLabel = 'WhatsApp del ingeniero';
