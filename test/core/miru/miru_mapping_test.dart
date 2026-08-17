import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/miru/miru_mapping.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/models/video_source.dart';

void main() {
  const sourceId = 'miru:demo';

  test('list items map onto MediaItem with the Miru url as id/url', () {
    final items = mediaItemsFromMiruList(
      [
        {'title': 'Show', 'url': '/s1', 'cover': 'https://c/1.jpg'},
        {'title': 'Other', 'url': '/s2'},
      ],
      sourceId: sourceId,
      type: ProviderType.anime,
    );
    expect(items, hasLength(2));
    expect(items.first.id, '/s1');
    expect(items.first.url, '/s1');
    expect(items.first.title, 'Show');
    expect(items.first.cover, 'https://c/1.jpg');
    expect(items.first.sourceId, sourceId);
    expect(items.first.type, ProviderType.anime);
  });

  test('detail.episodes flatten url groups into Episode.season', () {
    final detail = mediaDetailFromMiru(
      j: {
        'title': 'Show',
        'cover': 'https://c/1.jpg',
        'desc': 'A show.',
        'episodes': [
          {
            'title': 'Season 1',
            'urls': [
              {'name': 'Ep 1', 'url': '/e1'},
              {'name': 'Ep 2', 'url': '/e2'},
            ],
          },
          {
            'title': 'OVA',
            'urls': [
              {'name': 'OVA 1', 'url': '/ova'},
            ],
          },
        ],
      },
      url: '/show',
      sourceId: sourceId,
      type: ProviderType.anime,
    );
    expect(detail.title, 'Show');
    expect(detail.description, 'A show.');
    expect(detail.episodes, hasLength(3));
    expect(detail.episodes[0].title, 'Ep 1');
    expect(detail.episodes[0].season, 1);
    expect(detail.episodes[2].title, 'OVA 1');
    expect(detail.episodes[2].season, 2);
    expect(detail.episodes[2].url, '/ova');
  });

  test('bangumi watch maps hls / headers / subtitles onto VideoSource', () {
    final sources = videoSourcesFromMiruWatch({
      'type': 'hls',
      'url': 'https://cdn/a.m3u8',
      'headers': {'Referer': 'https://x'},
      'subtitles': [
        {'url': 'https://cdn/en.vtt', 'lang': 'en', 'title': 'English'},
      ],
    });
    expect(sources, hasLength(1));
    expect(sources.single.url, 'https://cdn/a.m3u8');
    expect(sources.single.container, SourceContainer.hls);
    expect(sources.single.headers, {'Referer': 'https://x'});
    expect(sources.single.subtitles.single.lang, 'en');
    expect(sources.single.subtitles.single.label, 'English');
  });

  test('manga watch maps urls[] onto PageImage', () {
    final pages = pagesFromMiruWatch({
      'urls': ['https://cdn/p1.jpg', 'https://cdn/p2.jpg'],
      'headers': {'User-Agent': 'miru'},
    });
    expect(pages.map((p) => p.url), ['https://cdn/p1.jpg', 'https://cdn/p2.jpg']);
    expect(pages.first.headers, {'User-Agent': 'miru'});
  });

  test('fikushon watch joins content[] into ChapterText html', () {
    final text = textFromMiruWatch({
      'title': 'Chapter 1',
      'content': ['Hello', 'World'],
    });
    expect(text.title, 'Chapter 1');
    expect(text.html, '<p>Hello</p><p>World</p>');
  });
}
