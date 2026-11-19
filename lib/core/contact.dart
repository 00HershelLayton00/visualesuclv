import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';

/// Abre WhatsApp con el contacto del ingeniero (donaciones o peticiones).
Future<void> openEngineerContact(BuildContext context) async {
  final uri = Uri.parse(contactUrl);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) return;
  } catch (_) {
    // Se muestra el enlace como respaldo.
  }
  messenger.showSnackBar(
    SnackBar(content: Text('No se pudo abrir WhatsApp. Enlace: $contactUrl')),
  );
}
