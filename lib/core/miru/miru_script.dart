import '../models/provider_info.dart';

/// Parsed `// ==MiruExtension==` header. Fields match the classic miru-app
/// catalog (`index.json`) plus the JS-source tags that index generation
/// copies out of each file.
class MiruExtensionMeta {
  const MiruExtensionMeta({
    required this.package,
    required this.name,
    required this.version,
    required this.lang,
    required this.type,
    required this.webSite,
    this.author = '',
    this.license = '',
    this.icon = '',
    this.description = '',
    this.nsfw = false,
    this.url = '',
    this.repoUrl = '',
    this.enabled = true,
  });

  final String package;
  final String name;
  final String version;
  final String lang;

  /// Miru `@type`: `bangumi`, `manga`, or `fikushon`.
  final String type;
  final String webSite;
  final String author;
  final String license;
  final String icon;
  final String description;
  final bool nsfw;

  /// Catalog filename (`345movie.net.js`) when known.
  final String url;

  /// Origin repo index URL the extension was installed from.
  final String repoUrl;

  /// User toggle. Installed stays installed; disabled sources are omitted
  /// from search and the source picker. Defaults on (missing Hive key = on).
  final bool enabled;

  String get sourceId => 'miru:$package';

  ProviderType get providerType => providerTypeForMiruType(type);

  MiruExtensionMeta copyWith({String? repoUrl, String? url, bool? enabled}) =>
      MiruExtensionMeta(
        package: package,
        name: name,
        version: version,
        lang: lang,
        type: type,
        webSite: webSite,
        author: author,
        license: license,
        icon: icon,
        description: description,
        nsfw: nsfw,
        url: url ?? this.url,
        repoUrl: repoUrl ?? this.repoUrl,
        enabled: enabled ?? this.enabled,
      );

  factory MiruExtensionMeta.fromMap(Map<dynamic, dynamic> j) =>
      MiruExtensionMeta(
        package: (j['package'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        version: (j['version'] as String?) ?? '',
        lang: (j['lang'] as String?) ?? '',
        type: (j['type'] as String?) ?? 'bangumi',
        webSite: (j['webSite'] as String?) ?? (j['website'] as String?) ?? '',
        author: (j['author'] as String?) ?? '',
        license: (j['license'] as String?) ?? '',
        icon: (j['icon'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        nsfw: j['nsfw'] == true || j['nsfw'] == 'true',
        url: (j['url'] as String?) ?? '',
        repoUrl: (j['repoUrl'] as String?) ?? '',
        enabled: j['enabled'] != false,
      );

  Map<String, dynamic> toMap() => {
    'package': package,
    'name': name,
    'version': version,
    'lang': lang,
    'type': type,
    'webSite': webSite,
    'author': author,
    'license': license,
    'icon': icon,
    'description': description,
    'nsfw': nsfw,
    'url': url,
    'repoUrl': repoUrl,
    'enabled': enabled,
  };
}

/// Maps Miru's `@type` onto the app's [ProviderType]. `bangumi` (any video)
/// is anime so it lives in Streaming mode; unknown values do the same.
ProviderType providerTypeForMiruType(String type) => switch (type.trim()) {
  'manga' => ProviderType.manga,
  'fikushon' => ProviderType.novel,
  _ => ProviderType.anime,
};

/// QuickJS-safe class identifier for [package], matching miru-app:
/// strip dots, then if anything non-letter remains strip those and append
/// `Renamed` (`345movie.net` → `movienetRenamed`).
String sanitizeMiruClassName(String package) {
  var className = package.replaceAll('.', '');
  if (!RegExp(r'^[A-Za-z]+$').hasMatch(className)) {
    className =
        '${className.replaceAll(RegExp(r'[^A-Za-z]'), '')}Renamed';
  }
  if (className.isEmpty) className = 'ExtRenamed';
  // A leading digit is already gone (non-letter), but keep a valid ident.
  if (!RegExp(r'^[A-Za-z_]').hasMatch(className)) className = 'E$className';
  return className;
}

/// Rewrites `export default class … {` to `class [className] extends Extension {`
/// so the harness can instantiate it. Same transform miru-app applies.
String rewriteMiruExport(String source, String className) => source.replaceFirst(
  RegExp(r'export\s+default\s+class[^{]*\{'),
  'class $className extends Extension {',
);

/// Joins `@webSite` (or `Miru-Url`) with the relative [url] the extension
/// passed to `this.request`. Concatenation is exact — miru-app does not
/// insert slashes.
String joinMiruRequestUrl({
  required String webSite,
  required String url,
  Map? options,
}) {
  final headers = options?['headers'];
  String? override;
  if (headers is Map) {
    for (final e in headers.entries) {
      if (e.key.toString().toLowerCase() == 'miru-url') {
        override = e.value?.toString();
        break;
      }
    }
  }
  final base = (override != null && override.isNotEmpty) ? override : webSite;
  return '$base$url';
}

/// Parses the `// ==MiruExtension==` … `// ==/MiruExtension==` block.
/// Throws [FormatException] when the block is missing or `@package` is empty.
MiruExtensionMeta parseMiruExtension(String source) {
  final block = RegExp(
    r'//\s*==MiruExtension==([\s\S]*?)//\s*==/MiruExtension==',
  ).firstMatch(source);
  if (block == null) {
    throw const FormatException('Not a Miru extension (missing header)');
  }
  final tags = <String, String>{};
  for (final line in block.group(1)!.split('\n')) {
    final m = RegExp(r'^//\s*@(\w+)\s+(.*)$').firstMatch(line.trim());
    if (m == null) continue;
    tags[m.group(1)!] = m.group(2)!.trim();
  }
  final package = tags['package'] ?? '';
  if (package.isEmpty) {
    throw const FormatException('Miru extension is missing @package');
  }
  return MiruExtensionMeta(
    package: package,
    name: tags['name'] ?? package,
    version: tags['version'] ?? '',
    lang: tags['lang'] ?? '',
    type: tags['type'] ?? 'bangumi',
    webSite: tags['webSite'] ?? '',
    author: tags['author'] ?? '',
    license: tags['license'] ?? '',
    icon: tags['icon'] ?? '',
    description: tags['description'] ?? '',
    nsfw: tags['nsfw'] == 'true',
  );
}
