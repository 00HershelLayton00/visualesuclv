import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'url_utils.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;
}

/// Cliente HTTP del sitio, con deteccion automatica de esquema
/// (https y respaldo http) y cabeceras uniformes.
class ApiClient {
  ApiClient(this._preferences, {http.Client? client})
    : _client = client ?? http.Client() {
    _scheme = _preferences.getString(_schemeKey) ?? 'https';
  }

  static const String _schemeKey = 'server_scheme';
  static const String host = 'visuales.uclv.cu';
  static const String userAgent = 'VisualesUCLV/1.0 (Android)';

  final SharedPreferences _preferences;
  final http.Client _client;

  late String _scheme;
  Dio? _dio;

  String get scheme => _scheme;
  String get baseUrl => '$_scheme://$host';
  Uri get baseUri => Uri.parse('$baseUrl/');

  Future<bool> _switchScheme() async {
    _scheme = _scheme == 'https' ? 'http' : 'https';
    _dio = null;
    await _preferences.setString(_schemeKey, _scheme);
    return true;
  }

  Future<String> getText(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    bool allowRetry = true,
  }) async {
    final target = collapseSlashes(url);
    try {
      final response = await _client
          .get(
            Uri.parse(target),
            headers: const {
              'User-Agent': userAgent,
              'Accept': 'text/html,text/plain,*/*',
            },
          )
          .timeout(timeout);
      if (response.statusCode >= 400) {
        throw ApiException(
          _statusMessage(response.statusCode),
          statusCode: response.statusCode,
        );
      }
      return response.body;
    } on ApiException {
      rethrow;
    } catch (error) {
      final canRetryWithOtherScheme =
          error is SocketException ||
          error is HandshakeException ||
          error is http.ClientException;
      if (allowRetry && canRetryWithOtherScheme) {
        await _switchScheme();
        try {
          return await getText(url, timeout: timeout, allowRetry: false);
        } catch (_) {
          // Continua con el error original.
        }
      }
      throw ApiException(_friendlyError(error));
    }
  }

  /// Dio configurado para descargas y streaming.
  Dio createDio() {
    return _dio ??= Dio(
      BaseOptions(
        headers: {'User-Agent': userAgent},
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(seconds: 60),
        followRedirects: true,
        maxRedirects: 8,
        validateStatus: (status) => status != null && status < 400,
      ),
    );
  }

  void dispose() {
    _client.close();
    _dio?.close(force: true);
  }

  static String _statusMessage(int statusCode) {
    switch (statusCode) {
      case 403:
        return 'Acceso denegado (403). Este contenido parece estar '
            'restringido para tu red.';
      case 404:
        return 'La carpeta o el archivo ya no existe (404).';
      case 500:
      case 502:
      case 503:
        return 'El servidor no responde correctamente ($statusCode).';
      default:
        return 'Error del servidor ($statusCode).';
    }
  }

  static String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return 'El servidor tardo demasiado en responder. Comprueba tu conexion.';
    }
    if (error is SocketException) {
      return 'No hay conexion con visuales.uclv.cu. Recuerda que solo '
          'esta disponible desde la red de Cuba.';
    }
    if (error is HandshakeException) {
      return 'No se pudo establecer una conexion segura.';
    }
    return 'No se pudo completar la operacion. Intenta de nuevo.';
  }
}
