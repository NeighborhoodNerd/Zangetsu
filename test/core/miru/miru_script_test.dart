import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/miru/miru_script.dart';
import 'package:watch_app/core/models/provider_info.dart';

const _header = '''
// ==MiruExtension==
// @name      345Movie
// @package   345movie.net
// @version   0.0.3
// @author    appdevelpo
// @lang      en
// @license   MIT
// @icon      https://example.test/icon.png
// @webSite   https://345movie.net
// @nsfw      false
// @type      bangumi
// ==/MiruExtension==
''';

void main() {
  test('parseMiruExtension reads the ==MiruExtension== header', () {
    final meta = parseMiruExtension('$_header\nexport default class extends Extension {}');
    expect(meta.package, '345movie.net');
    expect(meta.name, '345Movie');
    expect(meta.version, '0.0.3');
    expect(meta.lang, 'en');
    expect(meta.type, 'bangumi');
    expect(meta.webSite, 'https://345movie.net');
    expect(meta.nsfw, isFalse);
    expect(meta.enabled, isTrue);
    expect(meta.sourceId, 'miru:345movie.net');
    expect(meta.providerType, ProviderType.anime);
  });

  test('parseMiruExtension maps manga / fikushon @type onto ProviderType', () {
    expect(
      parseMiruExtension(
        '// ==MiruExtension==\n// @package p\n// @type manga\n// ==/MiruExtension==',
      ).providerType,
      ProviderType.manga,
    );
    expect(
      parseMiruExtension(
        '// ==MiruExtension==\n// @package p\n// @type fikushon\n// ==/MiruExtension==',
      ).providerType,
      ProviderType.novel,
    );
  });

  test('parseMiruExtension throws when the header or @package is missing', () {
    expect(
      () => parseMiruExtension('export default class extends Extension {}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseMiruExtension(
        '// ==MiruExtension==\n// @name X\n// ==/MiruExtension==',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('sanitizeMiruClassName matches miru-app (alphabet-only, Renamed suffix)', () {
    expect(sanitizeMiruClassName('345movie.net'), 'movienetRenamed');
    expect(sanitizeMiruClassName('example.com'), 'examplecom');
    expect(sanitizeMiruClassName('123'), 'Renamed');
  });

  test('fromMap treats a missing enabled key as on', () {
    expect(
      MiruExtensionMeta.fromMap({'package': 'p', 'name': 'N'}).enabled,
      isTrue,
    );
  });

  test('fromMap reads enabled: false', () {
    expect(
      MiruExtensionMeta.fromMap({'package': 'p', 'enabled': false}).enabled,
      isFalse,
    );
  });

  test('rewriteMiruExport replaces export default class with a named class', () {
    const src = 'export default class extends Extension {\n  latest() {}\n}';
    final out = rewriteMiruExport(src, 'movienetRenamed');
    expect(out, startsWith('class movienetRenamed extends Extension {'));
    expect(out, isNot(contains('export default')));
  });

  group('joinMiruRequestUrl', () {
    test('concatenates @webSite + path with no extra slash', () {
      expect(
        joinMiruRequestUrl(
          webSite: 'https://345movie.net',
          url: '/movie/1',
        ),
        'https://345movie.net/movie/1',
      );
    });

    test('Miru-Url header overrides the base (case-insensitive)', () {
      expect(
        joinMiruRequestUrl(
          webSite: 'https://345movie.net',
          url: '/alt',
          options: {
            'headers': {'Miru-Url': 'https://cdn.example'},
          },
        ),
        'https://cdn.example/alt',
      );
      expect(
        joinMiruRequestUrl(
          webSite: 'https://345movie.net',
          url: '/x',
          options: {
            'headers': {'miru-url': 'https://other.test'},
          },
        ),
        'https://other.test/x',
      );
    });
  });
}
