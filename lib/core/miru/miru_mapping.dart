import '../models/episode.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/page_content.dart';
import '../models/provider_info.dart';
import '../models/video_source.dart';
import 'miru_script.dart';

MediaItem mediaItemFromMiruList(
  Map<dynamic, dynamic> j, {
  required String sourceId,
  required ProviderType type,
}) {
  final url = (j['url'] as String?) ?? '';
  return MediaItem(
    id: url,
    title: (j['title'] as String?) ?? '',
    cover: j['cover'] as String?,
    url: url,
    type: type,
    sourceId: sourceId,
  );
}

List<MediaItem> mediaItemsFromMiruList(
  dynamic raw, {
  required String sourceId,
  required ProviderType type,
}) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map)
        mediaItemFromMiruList(e, sourceId: sourceId, type: type),
  ];
}

MediaDetail mediaDetailFromMiru({
  required Map<dynamic, dynamic> j,
  required String url,
  required String sourceId,
  required ProviderType type,
}) {
  final meta = j['metadata'];
  final genres = <String>[];
  final studios = <String>[];
  if (meta is Map) {
    for (final e in meta.entries) {
      final key = e.key.toString().toLowerCase();
      final value = e.value?.toString() ?? '';
      if (value.isEmpty) continue;
      if (key.contains('genre')) {
        genres.addAll(
          value.split(RegExp(r'[,/|]')).map((s) => s.trim()).where((s) => s.isNotEmpty),
        );
      } else if (key.contains('studio') ||
          key.contains('author') ||
          key.contains('artist')) {
        studios.add(value);
      }
    }
  }
  return MediaDetail(
    id: url,
    title: (j['title'] as String?) ?? '',
    cover: j['cover'] as String?,
    url: url,
    description: j['desc'] as String?,
    genres: genres,
    studios: studios,
    episodes: episodesFromMiruDetail(j),
    type: type,
    sourceId: sourceId,
  );
}

/// Flattens Miru's grouped `episodes[{title, urls:[{name,url}]}]` into
/// [Episode]s. Group index (1-based) is stored as [Episode.season].
List<Episode> episodesFromMiruDetail(Map<dynamic, dynamic> j) {
  final groups = j['episodes'];
  if (groups is! List) return const [];
  final out = <Episode>[];
  var n = 0;
  for (var g = 0; g < groups.length; g++) {
    final group = groups[g];
    if (group is! Map) continue;
    final urls = group['urls'];
    if (urls is! List) continue;
    for (final u in urls) {
      if (u is! Map) continue;
      final epUrl = (u['url'] as String?) ?? '';
      final name = (u['name'] as String?) ?? '';
      n += 1;
      out.add(
        Episode(
          id: epUrl.isNotEmpty ? epUrl : 'ep-$n',
          title: name.isNotEmpty ? name : 'Episode $n',
          number: n.toDouble(),
          url: epUrl,
          season: g + 1,
        ),
      );
    }
  }
  return out;
}

List<VideoSource> videoSourcesFromMiruWatch(dynamic raw) {
  if (raw is! Map) return const [];
  final url = (raw['url'] as String?) ?? '';
  if (url.isEmpty) return const [];
  final type = (raw['type'] as String?)?.toLowerCase() ?? '';
  final container = switch (type) {
    'hls' => SourceContainer.hls,
    'mp4' => SourceContainer.mp4,
    'torrent' => SourceContainer.torrent,
    _ => SourceContainer.unknown,
  };
  Map<String, String>? headers;
  final h = raw['headers'];
  if (h is Map) {
    headers = {
      for (final e in h.entries) e.key.toString(): e.value.toString(),
    };
  }
  final subs = <Subtitle>[];
  final subRaw = raw['subtitles'];
  if (subRaw is List) {
    for (final s in subRaw) {
      if (s is! Map) continue;
      final su = (s['url'] as String?) ?? '';
      if (su.isEmpty) continue;
      subs.add(
        Subtitle(
          url: su,
          lang: (s['lang'] as String?) ?? (s['language'] as String?) ?? '',
          label: s['title'] as String?,
        ),
      );
    }
  }
  return [
    VideoSource(
      url: url,
      container: container,
      headers: headers,
      subtitles: subs,
      label: raw['audioTrack'] as String?,
    ),
  ];
}

List<PageImage> pagesFromMiruWatch(dynamic raw) {
  if (raw is! Map) return const [];
  Map<String, String>? headers;
  final h = raw['headers'];
  if (h is Map) {
    headers = {
      for (final e in h.entries) e.key.toString(): e.value.toString(),
    };
  }
  final urls = raw['urls'];
  if (urls is! List) return const [];
  return [
    for (final u in urls)
      if (u is String && u.isNotEmpty) PageImage(url: u, headers: headers),
  ];
}

ChapterText textFromMiruWatch(dynamic raw) {
  if (raw is! Map) {
    throw StateError('Miru novel watch() did not return a chapter');
  }
  final content = raw['content'];
  final parts = content is List
      ? content.map((e) => e.toString()).where((s) => s.isNotEmpty)
      : const <String>[];
  final html = parts.map((p) => '<p>$p</p>').join();
  return ChapterText(
    html: html,
    title: raw['title'] as String?,
  );
}

ProviderInfo infoFromMiruMeta(MiruExtensionMeta meta) => ProviderInfo(
  name: meta.name,
  lang: meta.lang.isEmpty ? 'all' : meta.lang,
  baseUrl: meta.webSite,
  logo: meta.icon.isEmpty ? null : meta.icon,
  type: meta.providerType,
  version: meta.version.isEmpty ? null : meta.version,
);
