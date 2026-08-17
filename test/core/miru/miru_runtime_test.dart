import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/miru/miru_runtime.dart';
import 'package:watch_app/core/miru/miru_script.dart';

const _regexJs = r'''
// ==MiruExtension==
// @name      FakeRegex
// @package   fake.regex
// @version   1.0.0
// @lang      en
// @webSite   https://regex.test
// @type      bangumi
// ==/MiruExtension==
export default class extends Extension {
  async latest(page) {
    return [{title: 'Show', url: '/s' + page, cover: ''}];
  }
  async watch(url) {
    return {type: 'hls', url: 'https://cdn' + url + '.m3u8'};
  }
}
''';

const _cssJs = r'''
// ==MiruExtension==
// @name      FakeCss
// @package   fake.css
// @version   1.0.0
// @lang      en
// @webSite   https://css.test
// @type      bangumi
// ==/MiruExtension==
export default class extends Extension {
  async latest(page) {
    const html = await this.request('/list');
    const title = await this.querySelector(html, 'a.title').text;
    const href = await this.getAttributeText(html, 'a.title', 'href');
    return [{title: title, url: href, cover: ''}];
  }
  async watch(url) {
    return {type: 'mp4', url: 'https://cdn/v.mp4'};
  }
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'regex fixture latest/watch never touches fetch',
    () async {
      final runtime = MiruRuntime(
        fetch: (url, init) async => throw StateError('fetch should not run: $url'),
      );
      final meta = parseMiruExtension(_regexJs);
      await runtime.loadExtension(meta, _regexJs);

      final latest = await runtime.call(meta.package, 'latest', [1]);
      expect(latest, [
        {'title': 'Show', 'url': '/s1', 'cover': ''},
      ]);

      final watch = await runtime.call(meta.package, 'watch', ['/e1']);
      expect(watch, {'type': 'hls', 'url': 'https://cdn/e1.m3u8'});

      runtime.dispose();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    'css fixture latest loads HTML through the outbox and cheerio',
    () async {
      final fetched = <String>[];
      final runtime = MiruRuntime(
        fetch: (url, init) async {
          fetched.add(url);
          return MiruHttpResponse(
            status: 200,
            body: '<a class="title" href="/item-1">Cool Show</a>',
            url: url,
          );
        },
      );
      final meta = parseMiruExtension(_cssJs);
      await runtime.loadExtension(meta, _cssJs);

      final latest = await runtime.call(meta.package, 'latest', [1]);
      expect(fetched, ['https://css.test/list']);
      expect(latest, [
        {'title': 'Cool Show', 'url': '/item-1', 'cover': ''},
      ]);

      runtime.dispose();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    'Miru-Url on this.request overrides @webSite',
    () async {
      final fetched = <String>[];
      const js = r'''
// ==MiruExtension==
// @name      FakeUrl
// @package   fake.url
// @version   1.0.0
// @lang      en
// @webSite   https://site.test
// @type      bangumi
// ==/MiruExtension==
export default class extends Extension {
  async latest(page) {
    return this.request('/alt', {headers: {'Miru-Url': 'https://cdn.example'}});
  }
}
''';
      final runtime = MiruRuntime(
        fetch: (url, init) async {
          fetched.add(url);
          return MiruHttpResponse(
            status: 200,
            body: '[{"title":"X","url":"/x"}]',
            url: url,
          );
        },
      );
      final meta = parseMiruExtension(js);
      await runtime.loadExtension(meta, js);
      final latest = await runtime.call(meta.package, 'latest', [1]);
      expect(fetched, ['https://cdn.example/alt']);
      expect(latest, [
        {'title': 'X', 'url': '/x'},
      ]);
      runtime.dispose();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    'search with an empty filter object does not throw on delete/entries',
    () async {
      const js = r'''
// ==MiruExtension==
// @name      FakeFilter
// @package   fake.filter
// @version   1.0.0
// @lang      en
// @webSite   https://f.test
// @type      bangumi
// ==/MiruExtension==
export default class extends Extension {
  async search(kw, page, filter) {
    delete filter["filter_main_bar"];
    var extra = "";
    for (const [key, value] of Object.entries(filter)) {
      extra += key + value.join(",");
    }
    return [{title: kw + extra, url: "/s", cover: ""}];
  }
}
''';
      final runtime = MiruRuntime(
        fetch: (url, init) async =>
            throw StateError('fetch should not run: $url'),
      );
      final meta = parseMiruExtension(js);
      await runtime.loadExtension(meta, js);

      final hits = await runtime.call(meta.package, 'search', [
        'naruto',
        1,
        <String, dynamic>{},
      ]);
      expect(hits, [
        {'title': 'naruto', 'url': '/s', 'cover': ''},
      ]);

      runtime.dispose();
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
