import 'package:flutter/foundation.dart';

import '../models/episode.dart';
import '../models/home_section.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/page_content.dart';
import '../models/provider_info.dart';
import '../models/video_source.dart';
import '../provider/base_provider.dart';
import '../provider/reading_provider.dart';
import 'miru_manager.dart';
import 'miru_mapping.dart';
import 'miru_script.dart';

/// One Miru extension wrapped as [BaseProvider] + [ReadingProvider].
///
/// Built from stored [MiruExtensionMeta] alone — constructing one never
/// builds the QuickJS runtime. Identified by `'miru:<package>'`.
class MiruProvider implements BaseProvider, ReadingProvider {
  MiruProvider({required this.manager, required this.meta});

  final MiruManager manager;
  final MiruExtensionMeta meta;

  @override
  String get sourceId => meta.sourceId;

  @override
  String get displayName => meta.name;

  bool get isBangumi => meta.providerType == ProviderType.anime;
  bool get isManga => meta.providerType == ProviderType.manga;
  bool get isNovel => meta.providerType == ProviderType.novel;

  @override
  Future<ProviderInfo> getInfo() async => infoFromMiruMeta(meta);

  @override
  Future<List<HomeSection>?> getHome({String category = 'sub'}) async {
    final items = await popular();
    return items.isEmpty
        ? null
        : [
            HomeSection(
              title: 'Latest',
              items: items,
              more: BrowseMore(sourceId: sourceId, kind: 'miru_latest'),
            ),
          ];
  }

  @override
  Future<List<MediaItem>> popular({
    String category = 'sub',
    int dateRange = 7,
    int page = 1,
  }) async {
    final raw = await _safeCall('latest', [page]);
    return mediaItemsFromMiruList(
      raw,
      sourceId: sourceId,
      type: meta.providerType,
    );
  }

  @override
  Future<List<MediaItem>> search(
    String query,
    int page, {
    String category = '',
  }) async {
    // Classic Miru search is `search(kw, page, filter)`. Extensions such as
    // 9animetv.to do `delete(filter["filter_main_bar"])` / Object.entries
    // without a null check, so the unfiltered path must pass `{}` not null.
    final raw = await _safeCall('search', [query, page, <String, dynamic>{}]);
    return mediaItemsFromMiruList(
      raw,
      sourceId: sourceId,
      type: meta.providerType,
    );
  }

  @override
  Future<MediaDetail> getDetail(String url, {String category = 'sub'}) async {
    final fallback = MediaDetail(
      id: url,
      title: '',
      url: url,
      type: meta.providerType,
      sourceId: sourceId,
    );
    final raw = await _safeCall('detail', [url]);
    if (raw is! Map) return fallback;
    return mediaDetailFromMiru(
      j: raw,
      url: url,
      sourceId: sourceId,
      type: meta.providerType,
    );
  }

  @override
  Future<List<Episode>> getEpisodes(String url, {String category = 'sub'}) async {
    final d = await getDetail(url, category: category);
    return d.episodes;
  }

  @override
  Future<List<VideoSource>> getVideoSources(
    String episodeUrl, {
    bool fast = false,
  }) async {
    if (!isBangumi) return const [];
    final raw = await _safeCall('watch', [episodeUrl]);
    return videoSourcesFromMiruWatch(raw);
  }

  @override
  Future<List<PageImage>> getPages(String chapterUrl) async {
    if (!isManga) return const [];
    final raw = await _safeCall('watch', [chapterUrl]);
    return pagesFromMiruWatch(raw);
  }

  @override
  Future<ChapterText> getText(String chapterUrl) async {
    if (!isNovel) {
      throw UnsupportedError(
        'MiruProvider ${meta.package} is not a novel source.',
      );
    }
    final raw = await _safeCall('watch', [chapterUrl]);
    return textFromMiruWatch(raw);
  }

  Future<dynamic> _safeCall(String method, List<Object?> args) async {
    try {
      return await manager.callPlugin(meta.package, method, args);
    } catch (e) {
      debugPrint('[miru] $method(${meta.package}) failed: $e');
      return null;
    }
  }
}
