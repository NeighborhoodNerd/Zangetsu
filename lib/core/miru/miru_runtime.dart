import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:html/dom.dart' as dom;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import 'miru_script.dart';

class MiruHttpResponse {
  const MiruHttpResponse({
    required this.status,
    required this.body,
    required this.url,
  });

  final int status;
  final String body;
  final String url;
}

/// Isolated QuickJS host for classic miru-app JS extensions. Twin of
/// [LnReaderRuntime]: fetch/settings/xpath go through an outbox so
/// `flutter test` works (sendMessage does not on the host FFI runtime).
class MiruRuntime {
  MiruRuntime({
    required Future<MiruHttpResponse> Function(String url, Map init) fetch,
    this.getSetting,
    this.registerSetting,
  }) : _fetch = fetch;

  final Future<MiruHttpResponse> Function(String url, Map init) _fetch;
  final Future<dynamic> Function(String package, String key)? getSetting;
  final Future<void> Function(String package, Map settings)? registerSetting;

  JavascriptRuntime? _rt;
  int _callSeq = 0;
  Future<void>? _readyFuture;

  Future<void> ensureReady() {
    if (_rt != null) return Future.value();
    return _readyFuture ??= _build();
  }

  Future<void> _build() async {
    try {
      final rt = getJavascriptRuntime(xhr: false);
      Future<void> evalAsset(String path) async {
        final src = await rootBundle.loadString(path);
        final r = rt.evaluate(src);
        if (r.isError) {
          rt.dispose();
          throw StateError('miru failed to load $path: ${r.stringResult}');
        }
      }

      await evalAsset('assets/js/lnreader_cheerio.js');
      await evalAsset('assets/js/miru_harness.js');
      rt.evaluate(
        'globalThis.window=globalThis; globalThis.self=globalThis; '
        'globalThis.global=globalThis;',
      );
      // UMD bundles assign onto `this`. `evaluate()` leaves `this` undefined,
      // so wrap with `.call(globalThis)` instead of loading them raw
      // (which segfaulted QuickJS in tests).
      for (final crypto in const [
        'assets/js/miru/md5.min.js',
        'assets/js/miru/jsencrypt.min.js',
        'assets/js/miru/crypto-js.min.js',
      ]) {
        try {
          final src = await rootBundle.loadString(crypto);
          final r = rt.evaluate(
            '(function(){\n$src\n}).call(globalThis);',
          );
          if (r.isError) {
            // Best-effort: extensions that never call CryptoJS still run.
          }
        } catch (_) {}
      }
      _rt = rt;
    } catch (_) {
      _readyFuture = null;
      rethrow;
    }
  }

  Future<String> loadExtension(MiruExtensionMeta meta, String jsSource) async {
    await ensureReady();
    final className = sanitizeMiruClassName(meta.package);
    final rewritten = rewriteMiruExport(jsSource, className);
    final result = await _awaitJs(
      '__loadExtension(${jsonEncode(meta.package)}, ${jsonEncode(className)}, '
      '${jsonEncode(rewritten)}, ${jsonEncode(jsonEncode(meta.toMap()))})',
      'load ${meta.package}',
    );
    return result?.toString() ?? meta.name;
  }

  Future<dynamic> call(String package, String method, List<Object?> args) =>
      _awaitJs(
        '__callExtension(${jsonEncode(package)},${jsonEncode(method)},'
        '${jsonEncode(jsonEncode(args))})',
        'call $package.$method',
      );

  Future<dynamic> _awaitJs(String expr, String label) async {
    await ensureReady();
    final rt = _rt!;
    final id = ++_callSeq;
    rt.evaluate(
      "globalThis.__calls=globalThis.__calls||{}; globalThis.__calls[$id]={done:false,result:null};"
      " Promise.resolve($expr).then("
      " function(r){globalThis.__calls[$id]={done:true,result:JSON.stringify(r===undefined?null:r)};},"
      " function(e){globalThis.__calls[$id]={done:true,result:JSON.stringify({__error:String((e&&e.message)||e)})};});",
    );
    final sw = Stopwatch()..start();
    while (sw.elapsed < const Duration(seconds: 30)) {
      rt.executePendingJob();
      final drained = rt.evaluate('__drainOutbox()').stringResult;
      for (final req in jsonDecode(drained) as List) {
        unawaited(_handleHost(req as Map<String, dynamic>));
      }
      final doneFlag = rt
          .evaluate(
            '(globalThis.__calls[$id]&&globalThis.__calls[$id].done)?"1":"0"',
          )
          .stringResult;
      if (doneFlag == '1') {
        final raw = rt.evaluate('globalThis.__calls[$id].result').stringResult;
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['__error'] != null) {
          throw StateError(decoded['__error'].toString());
        }
        return decoded;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw TimeoutException('miru $label timed out');
  }

  Future<void> _handleHost(Map<String, dynamic> map) async {
    final rt = _rt!;
    final reqId = map['id'];
    final kind = map['kind'] as String? ?? '';
    try {
      final result = await switch (kind) {
        'request' => _doRequest(map),
        'xpath' => _doXPath(map),
        'getSetting' => _doGetSetting(map),
        'registerSetting' => _doRegisterSetting(map),
        _ => throw StateError('unknown host kind: $kind'),
      };
      rt.evaluate(
        '__resolveHost(${jsonEncode(reqId)}, ${jsonEncode(jsonEncode(result))});',
      );
    } catch (e) {
      rt.evaluate(
        '__rejectHost(${jsonEncode(reqId)}, ${jsonEncode(e.toString())});',
      );
    }
  }

  Future<dynamic> _doRequest(Map<String, dynamic> map) async {
    final options = (map['options'] as Map?) ?? {};
    final url = joinMiruRequestUrl(
      webSite: map['webSite'] as String? ?? '',
      url: map['url'] as String? ?? '',
      options: options,
    );
    final headers = <String, dynamic>{};
    final rawHeaders = options['headers'];
    if (rawHeaders is Map) {
      for (final e in rawHeaders.entries) {
        if (e.key.toString().toLowerCase() == 'miru-url') continue;
        headers[e.key.toString()] = e.value;
      }
    }
    final init = {
      'method': (options['method'] as String?) ?? 'get',
      'headers': headers,
      'body': options['data'] ?? options['body'],
      'queryParameters': options['queryParameters'],
    };
    final resp = await _fetch(url, init);
    try {
      return jsonDecode(resp.body);
    } catch (_) {
      return resp.body;
    }
  }

  Future<dynamic> _doXPath(Map<String, dynamic> map) async {
    final content = map['content'] as String? ?? '';
    final selector = map['selector'] as String? ?? '';
    final fun = map['fun'] as String? ?? 'text';
    final xpath = HtmlXPath.html(content);
    final result = xpath.queryXPath(selector);
    String outer(dynamic node) {
      if (node is dom.Element) return node.outerHtml;
      return node?.toString() ?? '';
    }

    switch (fun) {
      case 'attr':
        return result.attr ?? '';
      case 'attrs':
        return result.attrs;
      case 'allHTML':
        return result.nodes.map((e) => outer(e.node)).toList().toString();
      case 'outerHTML':
        return outer(result.node?.node);
      case 'text':
      default:
        return result.node?.text ?? '';
    }
  }

  Future<dynamic> _doGetSetting(Map<String, dynamic> map) async {
    final fn = getSetting;
    if (fn == null) return null;
    return fn(map['package'] as String? ?? '', map['key'] as String? ?? '');
  }

  Future<dynamic> _doRegisterSetting(Map<String, dynamic> map) async {
    final fn = registerSetting;
    if (fn == null) return null;
    final settings = map['settings'];
    await fn(
      map['package'] as String? ?? '',
      settings is Map ? Map<String, dynamic>.from(settings) : const {},
    );
    return null;
  }

  Future<void> unloadExtension(String package) async {
    final rt = _rt;
    if (rt == null) return;
    rt.evaluate('__unloadExtension(${jsonEncode(package)})');
  }

  void dispose() {
    _rt?.dispose();
    _rt = null;
    _readyFuture = null;
  }
}
