import 'dart:convert';

import 'miru_script.dart';

const String kMiruReposBoxName = 'miru_repos';

/// Cleans a pasted Miru repo URL into an `index.json` fetch URL.
///
/// Accepts the GitHub repo, a directory, or the index itself. Never rejects —
/// unknown input is returned trimmed.
String normalizeMiruRepoUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();

  var stripped = true;
  while (stripped && s.length > 1) {
    stripped = false;
    for (final pair in const [
      ['<', '>'],
      ['"', '"'],
      ["'", "'"],
      ['`', '`'],
    ]) {
      if (s.startsWith(pair[0]) && s.endsWith(pair[1])) {
        s = s.substring(1, s.length - 1).trim();
        stripped = true;
        break;
      }
    }
  }

  if (!_hasScheme(s) && _looksLikeHost(s)) s = 'https://$s';

  final uri = Uri.tryParse(s);
  if (uri == null) return s;

  if (uri.host == 'github.com' || uri.host == 'www.github.com') {
    final segs = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (segs.length >= 2) {
      final owner = segs[0];
      final repo = segs[1];
      return 'https://raw.githubusercontent.com/$owner/$repo/main/index.json';
    }
  }

  if (uri.path.endsWith('/index.json')) return uri.toString();
  if (uri.path.isEmpty || uri.path == '/') {
    return uri.replace(path: '/index.json').toString();
  }
  if (uri.path.endsWith('/')) {
    return uri.replace(path: '${uri.path}index.json').toString();
  }
  return uri.toString();
}

bool _hasScheme(String s) =>
    RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s);

bool _looksLikeHost(String s) {
  final firstSlash = s.indexOf('/');
  final authority = firstSlash == -1 ? s : s.substring(0, firstSlash);
  if (authority.isEmpty || !authority.contains('.')) return false;
  if (authority.startsWith('.') || authority.endsWith('.')) return false;
  return RegExp(r'^[A-Za-z0-9.-]+(:[0-9]+)?$').hasMatch(authority);
}

/// Where a catalog entry's JS file lives, given the index URL that listed it.
String miruJsUrl(String indexUrl, String fileName) {
  final uri = Uri.parse(indexUrl);
  final segs = [...uri.pathSegments.where((s) => s.isNotEmpty)];
  if (segs.isNotEmpty && segs.last == 'index.json') segs.removeLast();
  segs.add('repo');
  segs.add(fileName);
  return uri.replace(path: '/${segs.join('/')}').toString();
}

List<MiruExtensionMeta> parseMiruIndex(String body, {String repoUrl = ''}) {
  final decoded = jsonDecode(body);
  final list = decoded is List
      ? decoded
      : (decoded is Map && decoded['data'] is List)
          ? decoded['data'] as List
          : throw const FormatException('Miru index.json is not an array');
  return [
    for (final e in list)
      if (e is Map) MiruExtensionMeta.fromMap(e).copyWith(repoUrl: repoUrl),
  ];
}
