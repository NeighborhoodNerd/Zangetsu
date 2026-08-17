import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/di/injector.dart' show sl;
import 'package:watch_app/core/miru/miru_extension_service.dart';
import 'package:watch_app/core/miru/miru_manager.dart';
import 'package:watch_app/core/miru/miru_script.dart';
import 'package:watch_app/core/mode/content_mode.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';
import 'package:watch_app/core/ui/source_switcher.dart';

MiruExtensionMeta _meta({
  required String package,
  required String name,
  required String type,
  bool nsfw = false,
}) =>
    MiruExtensionMeta(
      package: package,
      name: name,
      version: '1.0.0',
      lang: 'en',
      type: type,
      webSite: 'https://$package/',
      nsfw: nsfw,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MiruManager miruManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miru_registration_test');
    Hive.init(tempDir.path);
    await PlaybackPrefs.init();

    final service = MiruExtensionService(
      httpGet: (url) async => throw StateError('unexpected httpGet($url)'),
    );
    miruManager = MiruManager(
      service: service,
      fetch: (url, init) async => throw StateError(
        'fetch should not be called — installedSources/get never load the plugin',
      ),
    );
    await miruManager.init();
    final box = Hive.box<Map>(MiruExtensionService.boxName);
    for (final m in [
      _meta(package: 'bang.test', name: 'Bangumi Ext', type: 'bangumi'),
      _meta(package: 'manga.test', name: 'Manga Ext', type: 'manga'),
      _meta(package: 'novel.test', name: 'Novel Ext', type: 'fikushon'),
    ]) {
      await box.put(m.package, {...m.toMap(), 'js': ''});
    }
    sl.registerSingleton<MiruManager>(miruManager);
  });

  tearDown(() async {
    await sl.reset();
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('sourceTypeOf types each miru: id from stored @type, not the prefix', () {
    expect(sourceTypeOf('miru:bang.test'), ProviderType.anime);
    expect(sourceTypeOf('miru:manga.test'), ProviderType.manga);
    expect(sourceTypeOf('miru:novel.test'), ProviderType.novel);
  });

  test(
    'filterSourcesForMode places each @type in its own mode',
    () {
      final srcs = {
        'miru:bang.test': sourceTypeOf('miru:bang.test'),
        'miru:manga.test': sourceTypeOf('miru:manga.test'),
        'miru:novel.test': sourceTypeOf('miru:novel.test'),
        'ani:1': sourceTypeOf('ani:1'),
        'mihon:7': sourceTypeOf('mihon:7'),
        'lnr:plugin-a': sourceTypeOf('lnr:plugin-a'),
      };

      final anime = filterSourcesForMode(srcs, ContentMode.anime, (t) => t);
      expect(anime.keys, containsAll(['miru:bang.test', 'ani:1']));
      expect(anime.keys, isNot(contains('miru:manga.test')));
      expect(anime.keys, isNot(contains('miru:novel.test')));

      final manga = filterSourcesForMode(srcs, ContentMode.manga, (t) => t);
      expect(manga.keys, containsAll(['miru:manga.test', 'mihon:7']));
      expect(manga.keys, isNot(contains('miru:bang.test')));

      final novel = filterSourcesForMode(srcs, ContentMode.novel, (t) => t);
      expect(novel.keys, containsAll(['miru:novel.test', 'lnr:plugin-a']));
      expect(novel.keys, isNot(contains('miru:bang.test')));
    },
  );

  test(
    'SourceRepository.loadedSources/displayName/hasSource/baseUrlFor see miru: ids',
    () {
      final repo = SourceRepository(
        manager: ProviderManager(dio: Dio()),
        csManager: CloudStreamManager(),
        aniManager: AniyomiManager(),
        miruManager: miruManager,
        activeSource: ActiveSourceCubit(),
        prefs: PlaybackPrefs(),
      );

      final ids = repo.loadedSources.map((s) => s.id).toList();
      expect(
        ids,
        containsAll(['miru:bang.test', 'miru:manga.test', 'miru:novel.test']),
      );
      expect(repo.displayName('miru:bang.test'), 'Bangumi Ext');
      expect(repo.hasSource('miru:manga.test'), isTrue);
      expect(repo.hasSource('miru:nope'), isFalse);
      expect(repo.baseUrlFor('miru:novel.test'), 'https://novel.test/');
    },
  );

  test('omitting miruManager leaves miru: ids unresolvable, not a crash', () {
    final repo = SourceRepository(
      manager: ProviderManager(dio: Dio()),
      csManager: CloudStreamManager(),
      aniManager: AniyomiManager(),
      activeSource: ActiveSourceCubit(),
      prefs: PlaybackPrefs(),
    );
    expect(repo.hasSource('miru:bang.test'), isFalse);
    expect(
      repo.loadedSources.map((s) => s.id),
      isNot(contains('miru:bang.test')),
    );
  });

  test(
    'registering/listing a miru: source never builds the QuickJS runtime',
    () {
      final repo = SourceRepository(
        manager: ProviderManager(dio: Dio()),
        csManager: CloudStreamManager(),
        aniManager: AniyomiManager(),
        miruManager: miruManager,
        activeSource: ActiveSourceCubit(),
        prefs: PlaybackPrefs(),
      );
      expect(miruManager.installedSources.map((s) => s.id), contains('miru:bang.test'));
      expect(miruManager.get('miru:bang.test'), isNotNull);
      expect(repo.hasSource('miru:bang.test'), isTrue);
      expect(miruManager.runtimeBuilt, isFalse);
    },
  );

  test('an NSFW miru source is hidden while nsfwSources is off', () async {
    final prefs = PlaybackPrefs();
    await prefs.setNsfwSources(false);
    await Hive.box<Map>(MiruExtensionService.boxName).put(
      'nsfw.test',
      {
        ..._meta(
          package: 'nsfw.test',
          name: 'NSFW Ext',
          type: 'bangumi',
          nsfw: true,
        ).toMap(),
        'js': '',
      },
    );

    var ids = SourceRepository(
      manager: ProviderManager(dio: Dio()),
      csManager: CloudStreamManager(),
      aniManager: AniyomiManager(),
      miruManager: miruManager,
      activeSource: ActiveSourceCubit(),
      prefs: prefs,
    ).loadedSources.map((s) => s.id);
    expect(ids, isNot(contains('miru:nsfw.test')));

    await prefs.setNsfwSources(true);
    ids = SourceRepository(
      manager: ProviderManager(dio: Dio()),
      csManager: CloudStreamManager(),
      aniManager: AniyomiManager(),
      miruManager: miruManager,
      activeSource: ActiveSourceCubit(),
      prefs: prefs,
    ).loadedSources.map((s) => s.id);
    expect(ids, contains('miru:nsfw.test'));

    await prefs.setNsfwSources(false);
  });

  test(
    'a disabled miru source stays installed but is omitted from loadedSources',
    () async {
      await miruManager.setEnabled('bang.test', false);
      expect(miruManager.runtimeBuilt, isFalse);
      expect(miruManager.get('miru:bang.test')?.meta.enabled, isFalse);

      final repo = SourceRepository(
        manager: ProviderManager(dio: Dio()),
        csManager: CloudStreamManager(),
        aniManager: AniyomiManager(),
        miruManager: miruManager,
        activeSource: ActiveSourceCubit(),
        prefs: PlaybackPrefs(),
      );
      final ids = repo.loadedSources.map((s) => s.id).toList();
      expect(ids, isNot(contains('miru:bang.test')));
      expect(ids, containsAll(['miru:manga.test', 'miru:novel.test']));
      expect(repo.hasSource('miru:bang.test'), isTrue);

      await miruManager.setEnabled('bang.test', true);
      expect(miruManager.runtimeBuilt, isFalse);
      expect(
        repo.loadedSources.map((s) => s.id),
        contains('miru:bang.test'),
      );
    },
  );
}
