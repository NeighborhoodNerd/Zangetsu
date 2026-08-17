import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/app_config.dart';
import 'package:watch_app/core/miru/miru_repo.dart';

void main() {
  group('normalizeMiruRepoUrl', () {
    test('rewrites a GitHub repo URL to raw index.json on main', () {
      expect(
        normalizeMiruRepoUrl('https://github.com/miru-project/repo'),
        'https://raw.githubusercontent.com/miru-project/repo/main/index.json',
      );
    });

    test('appends index.json to a trailing-slash directory', () {
      expect(
        normalizeMiruRepoUrl('https://example.test/miru/'),
        'https://example.test/miru/index.json',
      );
    });

    test('leaves an index.json URL alone', () {
      expect(
        normalizeMiruRepoUrl(kMiruOfficialRepoUrl),
        kMiruOfficialRepoUrl,
      );
    });

    test('strips markdown angle brackets', () {
      expect(
        normalizeMiruRepoUrl('<https://github.com/miru-project/repo>'),
        'https://raw.githubusercontent.com/miru-project/repo/main/index.json',
      );
    });
  });

  test('miruJsUrl puts the catalog file under /repo/', () {
    expect(
      miruJsUrl(kMiruOfficialRepoUrl, '345movie.net.js'),
      'https://raw.githubusercontent.com/miru-project/repo/main/repo/345movie.net.js',
    );
  });

  test('parseMiruIndex reads a stub index.json array', () {
    const body = '''
[
  {
    "package": "345movie.net",
    "name": "345Movie",
    "version": "0.0.3",
    "lang": "en",
    "type": "bangumi",
    "webSite": "https://345movie.net",
    "url": "345movie.net.js",
    "nsfw": false
  },
  {
    "package": "manga.test",
    "name": "Manga Test",
    "version": "1.0.0",
    "lang": "en",
    "type": "manga",
    "webSite": "https://manga.test",
    "url": "manga.test.js"
  }
]
''';
    final list = parseMiruIndex(body, repoUrl: kMiruOfficialRepoUrl);
    expect(list, hasLength(2));
    expect(list[0].package, '345movie.net');
    expect(list[0].type, 'bangumi');
    expect(list[0].url, '345movie.net.js');
    expect(list[0].repoUrl, kMiruOfficialRepoUrl);
    expect(list[1].type, 'manga');
  });

  test('parseMiruIndex throws when the body is not an array', () {
    expect(() => parseMiruIndex('{"oops":true}'), throwsFormatException);
  });
}
