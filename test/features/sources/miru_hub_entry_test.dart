import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/mihon/mihon_manager.dart';
import 'package:watch_app/core/miru/miru_extension_service.dart';
import 'package:watch_app/core/miru/miru_manager.dart';
import 'package:watch_app/core/miru/miru_repo.dart';
import 'package:watch_app/core/miru/miru_script.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/provider/provider_repo_registry.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';
import 'package:watch_app/features/sources/miru_sources_screen.dart';
import 'package:watch_app/features/sources/providers_hub_screen.dart';

class _FakeProviderRegistry implements ProviderRegistry {
  _FakeProviderRegistry(this._entries);
  final List<ProviderRegistryEntry> _entries;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<ProviderRegistryEntry> getAll() => _entries;

  @override
  ProviderRegistryEntry? entryFor(String sourceId) {
    for (final e in _entries) {
      if (e.name == sourceId) return e;
    }
    return null;
  }

  @override
  Set<String> nsfwSourceIds() => const {};

  @override
  String? typeOf(String sourceId) => null;

  @override
  Stream<BoxEvent> watch() => const Stream<BoxEvent>.empty();
}

class _FakeReposRegistry implements ProviderReposRegistry {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<ProviderRepo> getAll() => const [];

  @override
  Stream<BoxEvent> watch() => const Stream<BoxEvent>.empty();
}

class _FakeMiruService extends MiruExtensionService {
  _FakeMiruService() : super(httpGet: (_) async => '');
  final Map<String, MiruExtensionMeta> _installed = {};

  void seed(MiruExtensionMeta meta) => _installed[meta.package] = meta;

  @override
  Future<List<MiruExtensionMeta>> fetchIndex(String indexUrl) async => const [];
  @override
  Future<void> install(MiruExtensionMeta meta) async =>
      _installed[meta.package] = meta;
  @override
  List<MiruExtensionMeta> installed() => _installed.values.toList();
  @override
  Future<void> uninstall(String package) async => _installed.remove(package);

  @override
  Future<void> setEnabled(String package, bool enabled) async {
    final m = _installed[package];
    if (m == null) return;
    _installed[package] = m.copyWith(enabled: enabled);
  }

  @override
  String? jsFor(String package) => _installed.containsKey(package) ? '/*js*/' : null;
}

const _bangumi = MiruExtensionMeta(
  package: 'bang.test',
  name: 'Bangumi Ext',
  version: '1.0.0',
  lang: 'en',
  type: 'bangumi',
  webSite: 'https://bang.test/',
);

void main() {
  final sl = GetIt.instance;
  late _FakeMiruService miruService;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('miru_hub_entry_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<String>(kMiruReposBoxName);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() {
    Hive.box<String>(kMiruReposBoxName).clear();
    final entries = [
      ProviderRegistryEntry(
        name: 'anime1',
        url: 'bundled://anime1',
        displayName: 'Anime One',
      ),
      ProviderRegistryEntry(
        name: 'anime2',
        url: 'bundled://anime2',
        displayName: 'Anime Two',
      ),
    ];
    miruService = _FakeMiruService();
    sl
      ..registerSingleton<AppMode>(const AppMode(isTv: false))
      ..registerSingleton<ProviderRegistry>(_FakeProviderRegistry(entries))
      ..registerSingleton<ProviderReposRegistry>(_FakeReposRegistry())
      ..registerSingleton<CloudStreamManager>(CloudStreamManager())
      ..registerSingleton<AniyomiManager>(AniyomiManager())
      ..registerSingleton<MihonManager>(MihonManager())
      ..registerSingleton<MiruExtensionService>(miruService)
      ..registerSingleton<MiruManager>(
        MiruManager(
          service: miruService,
          fetch: (url, init) async => throw StateError(
            'fetch should not be called — the hub never touches the runtime',
          ),
        ),
      )
      ..registerSingleton<ActiveSourceCubit>(ActiveSourceCubit(fallback: ''));
  });

  tearDown(() async {
    await sl.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProvidersHubScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('Miru row shows under VIDEO + READING with its source count',
      (tester) async {
    miruService.seed(_bangumi);
    await pump(tester);

    expect(find.text('VIDEO + READING'), findsOneWidget);
    expect(find.text('Miru'), findsOneWidget);
    expect(find.text('Video, manga, and novel extensions'), findsOneWidget);
    expect(find.text('1 sources'), findsOneWidget);
  });

  testWidgets('tapping the Miru row pushes MiruSourcesScreen', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Miru'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MiruSourcesScreen), findsOneWidget);
  });

  testWidgets('Installed Miru sources have an enable switch', (tester) async {
    miruService.seed(_bangumi);
    await pump(tester);

    await tester.tap(find.text('Miru'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MiruSourcesScreen), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(miruService.installed().single.enabled, isFalse);
  });

  testWidgets(
    'Miru row is absent when MiruManager is not registered',
    (tester) async {
      await sl.unregister<MiruManager>();
      await sl.unregister<MiruExtensionService>();
      await pump(tester);

      expect(find.text('Miru'), findsNothing);
      expect(find.text('VIDEO + READING'), findsNothing);
    },
  );

  testWidgets(
    'a miru: active id badges the Miru row ACTIVE and does not badge Zangetsu',
    (tester) async {
      miruService.seed(_bangumi);
      await sl.unregister<ActiveSourceCubit>();
      sl.registerSingleton<ActiveSourceCubit>(
        ActiveSourceCubit(fallback: 'miru:bang.test'),
      );
      await pump(tester);

      expect(find.text('ACTIVE'), findsOneWidget);
    },
  );

  testWidgets('a registered Miru source is included in the header total', (
    tester,
  ) async {
    miruService.seed(_bangumi);
    await pump(tester);

    expect(find.text('3 sources ready'), findsOneWidget);
  });
}
