/// Entrada del indice global de carpetas del sitio.
class SearchEntry {
  SearchEntry({required this.name, required this.url, required this.path});

  final String name;
  final String url;
  final String path;

  bool get isDirectory => url.endsWith('/');

  List<String> toJson() => [name, url, path];

  static SearchEntry? fromJson(dynamic data) {
    if (data is! List || data.length < 3) return null;
    return SearchEntry(
      name: data[0].toString(),
      url: data[1].toString(),
      path: data[2].toString(),
    );
  }
}
