// Classic miru-app extension host. CSS helpers run in-engine on the cheerio
// bundle (already evaluated). HTTP, settings, and XPath go through an outbox
// the Dart driver polls — sendMessage/onMessage does not work under flutter
// test's host QuickJS.

globalThis.__pending = {};
globalThis.__seq = 0;
globalThis.__outbox = [];
globalThis.__drainOutbox = function () {
  var o = globalThis.__outbox;
  globalThis.__outbox = [];
  return JSON.stringify(o);
};
globalThis.__resolveHost = function (id, json) {
  var p = globalThis.__pending[id];
  if (!p) return;
  delete globalThis.__pending[id];
  try { p.resolve(JSON.parse(json)); } catch (e) { p.reject(e); }
};
globalThis.__rejectHost = function (id, msg) {
  var p = globalThis.__pending[id];
  if (!p) return;
  delete globalThis.__pending[id];
  p.reject(new Error(msg));
};
function __hostCall(kind, payload) {
  return new Promise(function (resolve, reject) {
    var id = ++globalThis.__seq;
    globalThis.__pending[id] = { resolve: resolve, reject: reject };
    var item = { id: id, kind: kind };
    for (var k in payload) item[k] = payload[k];
    globalThis.__outbox.push(item);
  });
}

function __cheerioLoad(html) {
  var C = globalThis.__cheerio;
  if (!C) throw new Error('cheerio not loaded');
  var load = C.load || (C.default && C.default.load);
  if (typeof load !== 'function') throw new Error('cheerio.load missing');
  return load(String(html == null ? '' : html));
}
function __outerHtml($node) {
  if (!$node || !$node.length) return '';
  try {
    var outer = $node.prop && $node.prop('outerHTML');
    if (outer) return outer;
  } catch (e) {}
  return $node.toString() ? String($node.toString()) : '';
}

class Element {
  constructor(content, selector) {
    this.content = content == null ? '' : String(content);
    this.selector = selector || '';
  }
  async querySelector(selector) {
    var html = await this.outerHTML;
    return new Element(html, selector);
  }
  async execute(fun) {
    var $ = __cheerioLoad(this.content);
    var node = this.selector ? $(this.selector).first() : $.root();
    switch (fun) {
      case 'text':
        return (node && node.text) ? (node.text() || '') : '';
      case 'innerHTML':
        return (node && node.html) ? (node.html() || '') : '';
      case 'outerHTML':
      default:
        return __outerHtml(node);
    }
  }
  get text() { return this.execute('text'); }
  get outerHTML() { return this.execute('outerHTML'); }
  get innerHTML() { return this.execute('innerHTML'); }
  async removeSelector(selector) {
    var html = await this.outerHTML;
    var $ = __cheerioLoad(html);
    $(selector).remove();
    this.content = $.html() || '';
    this.selector = '';
    return this;
  }
  async getAttributeText(attr) {
    var $ = __cheerioLoad(this.content);
    var node = this.selector ? $(this.selector).first() : $.root();
    if (!node || !node.attr) return '';
    var v = node.attr(attr);
    return v == null ? '' : String(v);
  }
}

class XPathNode {
  constructor(content, selector) {
    this.content = content == null ? '' : String(content);
    this.selector = selector || '';
  }
  async execute(fun) {
    return __hostCall('xpath', {
      content: this.content,
      selector: this.selector,
      fun: fun || 'text',
    });
  }
  get attr() { return this.execute('attr'); }
  get attrs() { return this.execute('attrs'); }
  get text() { return this.execute('text'); }
  get allHTML() { return this.execute('allHTML'); }
  get outerHTML() { return this.execute('outerHTML'); }
}

class Extension {
  constructor() {
    this.package = '';
    this.name = '';
    this.webSite = '';
    this.settingKeys = [];
  }
  async request(url, options) {
    options = options || {};
    options.headers = options.headers || {};
    options.method = options.method || 'get';
    return __hostCall('request', {
      url: String(url || ''),
      webSite: this.webSite || '',
      options: options,
    });
  }
  querySelector(content, selector) {
    return new Element(content, selector);
  }
  queryXPath(content, selector) {
    return new XPathNode(content, selector);
  }
  async querySelectorAll(content, selector) {
    var $ = __cheerioLoad(content);
    var els = [];
    $(selector).each(function () {
      els.push(new Element(__outerHtml($(this)), ''));
    });
    return els;
  }
  async getAttributeText(content, selector, attr) {
    return new Element(content, selector).getAttributeText(attr);
  }
  latest(page) { throw new Error('not implement latest'); }
  popular(page) { throw new Error('not implement popular'); }
  search(kw, page, filter) { throw new Error('not implement search'); }
  createFilter(filter) { throw new Error('not implement createFilter'); }
  detail(url) { throw new Error('not implement detail'); }
  watch(url) { throw new Error('not implement watch'); }
  checkUpdate(url) { throw new Error('not implement checkUpdate'); }
  async getSetting(key) {
    return __hostCall('getSetting', { package: this.package, key: String(key) });
  }
  async registerSetting(settings) {
    if (settings && settings.key) this.settingKeys.push(settings.key);
    return __hostCall('registerSetting', {
      package: this.package,
      settings: settings,
    });
  }
  async load() {}
}

console.log = function () {
  var parts = [];
  for (var i = 0; i < arguments.length; i++) {
    var a = arguments[i];
    parts.push(typeof a === 'string' ? a : JSON.stringify(a));
  }
};

globalThis.Extension = Extension;
globalThis.Element = Element;
globalThis.XPathNode = XPathNode;
globalThis.__exts = globalThis.__exts || {};

globalThis.__loadExtension = function (pkg, className, src, metaJson) {
  (0, eval)(src + '\n;globalThis.__miruCtor = ' + className + ';');
  var Ctor = globalThis.__miruCtor;
  delete globalThis.__miruCtor;
  if (typeof Ctor !== 'function') {
    throw new Error('Miru class ' + className + ' did not evaluate');
  }
  var inst = new Ctor();
  var meta = {};
  try { meta = JSON.parse(metaJson); } catch (e) {}
  inst.package = pkg;
  inst.name = meta.name || pkg;
  inst.webSite = meta.webSite || '';
  globalThis.__exts[pkg] = inst;
  return Promise.resolve(inst.load()).then(function () {
    return inst.name || pkg;
  });
};

globalThis.__callExtension = function (pkg, method, argsJson) {
  var inst = globalThis.__exts[pkg];
  if (!inst) return Promise.reject(new Error('unknown extension: ' + pkg));
  var fn = inst[method];
  if (typeof fn !== 'function') {
    return Promise.reject(new Error('unknown method: ' + method));
  }
  var args = JSON.parse(argsJson);
  return Promise.resolve(fn.apply(inst, args));
};

globalThis.__unloadExtension = function (pkg) {
  if (globalThis.__exts) delete globalThis.__exts[pkg];
};
