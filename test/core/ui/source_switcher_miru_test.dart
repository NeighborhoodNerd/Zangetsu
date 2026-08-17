import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/di/injector.dart' show sl;
import 'package:watch_app/core/miru/miru_extension_service.dart';
import 'package:watch_app/core/miru/miru_manager.dart';
import 'package:watch_app/core/miru/miru_script.dart';
import 'package:watch_app/core/mode/content_mode.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/provider_downloader.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/ui/source_switcher.dart';

class _FakeManager implements ProviderRuntimeLoader {
  @override
  JsProvider? get(String id) => null;
  @override
  void load({
    required String sourceId,
    required String jsSource,
    String originRepoUrl = '',
    String displayName = '',
  }) {}
  @override
  void setSettings(String sourceId, Map<String, dynamic> settings) {}
  @override
  void remove(String id) {}
}

class _FakeFetcher implements ProviderJsFetcher {
  @override
  Future<CachedProvider> fetch({
    required String name,
    required String url,
    bool force = false,
  }) async =>
      CachedProvider(name: name, jsCode: '', url: url, fetchedAt: DateTime.now());
  @override
  Future<void> remove(String name) async {}
}

MiruExtensionMeta _meta(String package, String type, String name) =>
    MiruExtensionMeta(
      package: package,
      name: name,
      version: '1.0.0',
      lang: 'en',
      type: type,
      webSite: 'https://$package/',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MiruManager miruManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('src_switch_miru_test');
    Hive.init(tempDir.path);
    await ProviderRegistry.init();
    await PlaybackPrefs.init();
    await CloudStreamManager.init();

    sl.registerSingleton<ProviderRegistry>(
      ProviderRegistry(downloader: _FakeFetcher(), manager: _FakeManager()),
    );
    sl.registerSingleton<PlaybackPrefs>(PlaybackPrefs());
    sl.registerSingleton<CloudStreamManager>(CloudStreamManager());
    sl.registerSingleton<AniyomiManager>(AniyomiManager());

    final service = MiruExtensionService(
      httpGet: (url) async => throw StateError('unexpected httpGet($url)'),
    );
    miruManager = MiruManager(
      service: service,
      fetch: (url, init) async =>
          throw StateError('categorizedSources never loads a plugin'),
    );
    await miruManager.init();
    final box = Hive.box<Map>(MiruExtensionService.boxName);
    for (final m in [
      _meta('bang.test', 'bangumi', 'Bangumi Ext'),
      _meta('manga.test', 'manga', 'Manga Ext'),
      _meta('novel.test', 'fikushon', 'Novel Ext'),
    ]) {
      await box.put(m.package, {...m.toMap(), 'js': ''});
    }
    sl.registerSingleton<MiruManager>(miruManager);
  });

  tearDown(() async {
    await sl.reset();
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('bangumi / manga / fikushon land in the matching buckets', () {
    final b = categorizedSources();
    expect(
      b.anime.where((r) => r.id == 'miru:bang.test').single.label,
      'Miru · Bangumi Ext',
    );
    expect(
      b.manga.where((r) => r.id == 'miru:manga.test').single.label,
      'Miru · Manga Ext',
    );
    expect(
      b.novel.where((r) => r.id == 'miru:novel.test').single.label,
      'Miru · Novel Ext',
    );
    expect(b.anime.any((r) => r.id == 'miru:manga.test'), isFalse);
    expect(b.manga.any((r) => r.id == 'miru:bang.test'), isFalse);
    expect(miruManager.runtimeBuilt, isFalse);
  });

  test('hasReadingSourcesFor sees manga and novel Miru extensions', () {
    expect(hasReadingSourcesFor(ContentMode.manga), isTrue);
    expect(hasReadingSourcesFor(ContentMode.novel), isTrue);
  });

  test('a disabled miru source is omitted from categorizedSources', () async {
    await miruManager.setEnabled('bang.test', false);
    final b = categorizedSources();
    expect(b.anime.any((r) => r.id == 'miru:bang.test'), isFalse);
    expect(b.manga.any((r) => r.id == 'miru:manga.test'), isTrue);
    expect(miruManager.runtimeBuilt, isFalse);
  });

  test('enabledProviderCount includes enabled Miru sources and skips disabled',
      () async {
    expect(enabledProviderCount(), 3);
    await miruManager.setEnabled('bang.test', false);
    expect(enabledProviderCount(), 2);
    expect(miruManager.runtimeBuilt, isFalse);
  });
}
