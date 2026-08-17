import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/hive/safe_box.dart';

import '../models/provider_info.dart';
import 'miru_extension_service.dart';
import 'miru_provider.dart';
import 'miru_runtime.dart';
import 'miru_script.dart';

/// Owns the shared QuickJS runtime + installed Miru metadata. Twin of
/// [LnReaderManager]: [init]/[get]/[installedSources] never build the runtime.
class MiruManager {
  MiruManager({required this.service, required this.fetch});

  final MiruExtensionService service;
  final Future<MiruHttpResponse> Function(String url, Map init) fetch;

  MiruRuntime? _runtime;
  final Set<String> _loaded = {};
  final Map<String, MiruProvider> _providerCache = {};

  @visibleForTesting
  bool get runtimeBuilt => _runtime != null;

  Future<void> init() async {
    if (!Hive.isBoxOpen(MiruExtensionService.boxName)) {
      await openBoxSafely<Map>(MiruExtensionService.boxName);
    }
    if (!Hive.isBoxOpen(MiruExtensionService.settingsBoxName)) {
      await openBoxSafely<dynamic>(MiruExtensionService.settingsBoxName);
    }
  }

  List<({String id, String name})> get installedSources => [
    for (final m in service.installed()) (id: m.sourceId, name: m.name),
  ];

  ProviderType? providerTypeOf(String sourceId) => get(sourceId)?.meta.providerType;

  MiruProvider? get(String sourceId) {
    final pkg = sourceId.startsWith('miru:') ? sourceId.substring(5) : sourceId;
    final meta = metaFor(pkg);
    if (meta == null) return null;
    return _providerCache[pkg] ??= MiruProvider(manager: this, meta: meta);
  }

  MiruExtensionMeta? metaFor(String package) {
    for (final m in service.installed()) {
      if (m.package == package) return m;
    }
    return null;
  }

  int get updateCount => 0;

  Future<void> ensureLoaded(String package) async {
    if (_loaded.contains(package)) return;
    final js = service.jsFor(package);
    final meta = metaFor(package);
    if (js == null || meta == null) {
      throw StateError('miru extension "$package" is not installed');
    }
    final runtime = _runtime ??= MiruRuntime(
      fetch: fetch,
      getSetting: service.getSetting,
      registerSetting: service.registerSetting,
    );
    await runtime.loadExtension(meta, js);
    _loaded.add(package);
  }

  Future<dynamic> callPlugin(
    String package,
    String method,
    List<Object?> args,
  ) async {
    await ensureLoaded(package);
    return _runtime!.call(package, method, args);
  }

  Future<void> uninstall(String package) async {
    await service.uninstall(package);
    _providerCache.remove(package);
    _loaded.remove(package);
    if (runtimeBuilt) await _runtime!.unloadExtension(package);
  }

  Future<void> setEnabled(String package, bool enabled) async {
    await service.setEnabled(package, enabled);
    _providerCache.remove(package);
  }

  Future<void> install(MiruExtensionMeta meta) async {
    await service.install(meta);
    _providerCache.remove(meta.package);
    _loaded.remove(meta.package);
  }
}
