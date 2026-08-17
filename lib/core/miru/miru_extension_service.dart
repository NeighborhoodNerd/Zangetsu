import 'package:hive/hive.dart';

import '../app_config.dart';
import 'miru_repo.dart';
import 'miru_script.dart';

/// Fetches the Miru `index.json` catalog and stores installed extension JS
/// in the `miru_plugins` Hive box — twin of [LnReaderExtensionService].
class MiruExtensionService {
  MiruExtensionService({required this.httpGet});

  final Future<String> Function(String url) httpGet;

  static const String boxName = 'miru_plugins';
  static const String settingsBoxName = 'miru_settings';

  Box<Map> get _box => Hive.box<Map>(boxName);

  Box<dynamic> get _settings {
    if (!Hive.isBoxOpen(settingsBoxName)) {
      throw StateError('miru_settings box is not open');
    }
    return Hive.box<dynamic>(settingsBoxName);
  }

  Future<List<MiruExtensionMeta>> fetchIndex(String indexUrl) async {
    final url = normalizeMiruRepoUrl(indexUrl);
    final body = await httpGet(url);
    return parseMiruIndex(body, repoUrl: url);
  }

  Future<void> install(MiruExtensionMeta meta) async {
    final file = meta.url.isNotEmpty ? meta.url : '${meta.package}.js';
    final jsUrl = file.startsWith('http')
        ? file
        : miruJsUrl(
            meta.repoUrl.isNotEmpty ? meta.repoUrl : kMiruOfficialRepoUrl,
            file,
          );
    final js = await httpGet(jsUrl);
    // Prefer header-parsed identity when the downloaded source has one, so a
    // mismatched catalog row can't install under the wrong package.
    MiruExtensionMeta stored = meta;
    try {
      stored = parseMiruExtension(js).copyWith(
        repoUrl: meta.repoUrl,
        url: meta.url,
      );
    } catch (_) {}
    final prev = _box.get(stored.package);
    final enabled = prev?['enabled'] is bool
        ? prev!['enabled'] as bool
        : stored.enabled;
    await _box.put(stored.package, {
      ...stored.copyWith(enabled: enabled).toMap(),
      'js': js,
    });
  }

  List<MiruExtensionMeta> installed() =>
      _box.values.map(MiruExtensionMeta.fromMap).toList();

  Future<void> uninstall(String package) => _box.delete(package);

  Future<void> setEnabled(String package, bool enabled) async {
    final row = _box.get(package);
    if (row == null) return;
    await _box.put(package, {
      ...Map<dynamic, dynamic>.from(row),
      'enabled': enabled,
    });
  }

  String? jsFor(String package) => _box.get(package)?['js'] as String?;

  Future<void> registerSetting(String package, Map settings) async {
    final key = settings['key']?.toString();
    if (key == null || key.isEmpty) return;
    final boxKey = '$package::$key';
    final existing = _settings.get(boxKey);
    final map = <String, dynamic>{
      ...settings.map((k, v) => MapEntry(k.toString(), v)),
      'package': package,
    };
    if (existing is Map && existing['value'] != null) {
      map['value'] = existing['value'];
    } else {
      map['value'] = settings['value'] ?? settings['defaultValue'];
    }
    await _settings.put(boxKey, map);
  }

  Future<dynamic> getSetting(String package, String key) async {
    final raw = _settings.get('$package::$key');
    if (raw is Map) {
      return raw['value'] ?? raw['defaultValue'];
    }
    return null;
  }
}
