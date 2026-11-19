import 'package:flutter_test/flutter_test.dart';
import 'package:visuales_uclv/core/apache_parser.dart';
import 'package:visuales_uclv/core/formatters.dart';
import 'package:visuales_uclv/core/url_utils.dart';

const String _sampleTable = '''
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<html>
 <head><title>Index of /Peliculas</title></head>
 <body>
<h1>Index of /Peliculas</h1>
  <table>
   <tr><th valign="top"><img src="/icons/blank.gif" alt="[ICO]"></th><th><a href="?C=N;O=D">Name</a></th><th><a href="?C=M;O=A">Last modified</a></th><th><a href="?C=S;O=A">Size</a></th><th><a href="?C=D;O=A">Description</a></th></tr>
   <tr><th colspan="5"><hr></th></tr>
<tr><td valign="top"><img src="/icons/back.gif" alt="[PARENTDIR]"></td><td><a href="/">Parent Directory</a></td><td>&nbsp;</td><td align="right">  - </td><td>&nbsp;</td></tr>
<tr><td valign="top"><img src="/icons/folder.gif" alt="[DIR]"></td><td><a href="Cubanas/">Cubanas/</a></td><td align="right">2025-02-09 16:43  </td><td align="right">  - </td><td>&nbsp;</td></tr>
<tr><td valign="top"><img src="/icons/compressed.gif" alt="[   ]"></td><td><a href="master.zip">master.zip</a></td><td align="right">2025-01-22 14:43  </td><td align="right">491K </td><td>&nbsp;</td></tr>
  </table>
</body></html>
''';

void main() {
  group('parseApacheIndex', () {
    test('parsea carpetas y archivos del listado de Apache', () {
      final entries = parseApacheIndex(
        _sampleTable,
        'https://visuales.uclv.cu/Peliculas/',
      );
      expect(entries.length, 2);

      final folder = entries.first;
      expect(folder.name, 'Cubanas');
      expect(folder.isDirectory, isTrue);
      expect(folder.url, 'https://visuales.uclv.cu/Peliculas/Cubanas/');
      expect(folder.modified, DateTime(2025, 2, 9, 16, 43));

      final file = entries.last;
      expect(file.name, 'master.zip');
      expect(file.isDirectory, isFalse);
      expect(file.size, 491 * 1024);
    });

    test('decodifica nombres con caracteres especiales', () {
      const html = '''
      <table>
      <tr><td><img alt="[DIR]"></td><td><a href="Squid%20Game%20S03/">Squid Game S03/</a></td><td>2026-01-01 10:00</td><td>-</td><td></td></tr>
      </table>''';
      final entries = parseApacheIndex(
        html,
        'https://visuales.uclv.cu/Series/',
      );
      expect(entries.single.name, 'Squid Game S03');
      expect(
        entries.single.url,
        'https://visuales.uclv.cu/Series/Squid%20Game%20S03/',
      );
    });
  });

  group('url_utils', () {
    test('colapsa barras duplicadas', () {
      expect(
        collapseSlashes('http://visuales.uclv.cu//Cursos//A/'),
        'http://visuales.uclv.cu/Cursos/A/',
      );
    });

    test('calcula la carpeta padre', () {
      expect(
        parentUrlOf('https://visuales.uclv.cu/Series/NETFLIX/Dark/'),
        'https://visuales.uclv.cu/Series/NETFLIX/',
      );
      expect(parentUrlOf('https://visuales.uclv.cu/'), isNull);
    });

    test('genera ruta local segura', () {
      expect(
        localRelativePathOf(
          'https://visuales.uclv.cu/Peliculas/Cubanas/Una%3A%20peli%3F.mp4',
        ),
        'Peliculas/Cubanas/Una_ peli_.mp4',
      );
    });
  });

  group('formatters', () {
    test('foldText quita acentos y conserva longitud', () {
      expect(foldText('Películas y Música'), 'peliculas y musica');
      expect(foldText('Accion').length, 'Accion'.length);
    });

    test('formatBytes usa unidades legibles', () {
      expect(formatBytes(637), '637 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(491 * 1024), '491 KB');
      expect(formatBytes(4 * 1024 * 1024 + 400 * 1024), '4.4 MB');
    });

    test('formatCount separa miles', () {
      expect(formatCount(30006), '30 006');
      expect(formatCount(999), '999');
    });
  });
}
