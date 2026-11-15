// Run the real landing script against a small DOM to check the deployed /Intragram/ path.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const docs = path.join(__dirname, '../docs');
const html = fs.readFileSync(path.join(docs, 'index.html'), 'utf8');
const webHtml = fs.readFileSync(path.join(docs, 'web/lite.html'), 'utf8');
const source = fs.readFileSync(path.join(docs, 'scripts/landing.js'), 'utf8');
const anchors = [...html.matchAll(/<a\b[^>]*\bdata-web-link\b[^>]*>/g)].map(m => m[0]);
assert.ok(anchors.length >= 5, 'web entry must be reachable from desktop, mobile, hero and downloads');
const hrefs = anchors.map(tag => /\bhref="([^"]+)"/.exec(tag)[1]);
assert.ok(hrefs.every(href => href.startsWith('./web/')), 'web entry must work under GitHub Pages project paths');
assert.ok(hrefs.includes('./web/?mode=portal'), 'app invitations must have a direct entry');
assert.match(html, /WebRTC 암호화/);
assert.match(html, /App messages and files also use encrypted WebRTC/);
assert.match(html, /100 MiB/);
assert.match(html, /href="#install"/);

// Landing and lightweight-client assets must ship together without a CDN.
for (const relative of ['index.html', 'web/lite.html']) {
  const file = path.join(docs, relative);
  for (const match of fs.readFileSync(file, 'utf8').matchAll(/\b(?:src|href)="([^"]+)"/g)) {
    const value = match[1];
    if (/^(?:[a-z][a-z\d+.-]*:|#|\/\/)/i.test(value)) continue;
    const target = path.resolve(path.dirname(file), value.split(/[?#]/)[0]);
    assert.ok(fs.existsSync(target), `${relative}: missing ${value}`);
  }
}
for (const filename of fs.readdirSync(path.join(docs, 'web')).filter(name => name.endsWith('.mjs'))) {
  const file = path.join(docs, 'web', filename);
  for (const match of fs.readFileSync(file, 'utf8').matchAll(/\bfrom\s+['"]([^'"]+)['"]/g)) {
    assert.ok(match[1].startsWith('./'), `${filename}: module imports must be local`);
    assert.ok(fs.existsSync(path.resolve(path.dirname(file), match[1])), `${filename}: missing module`);
  }
}
assert.match(webHtml, /name="referrer" content="no-referrer"/);
assert.match(webHtml, /type="module" src="\.\/app\.mjs"/);

function element(attributes = {}) {
  return {
    attributes: { ...attributes }, listeners: {},
    getAttribute(key) { return this.attributes[key] ?? null; },
    setAttribute(key, value) { this.attributes[key] = value; },
    removeAttribute(key) { delete this.attributes[key]; },
    addEventListener(event, action) { this.listeners[event] = action; },
  };
}

for (const base of ['https://gnoyx2.github.io/Intragram/', 'http://localhost:8000/']) {
  const root = element({ 'data-theme': 'dark' });
  root.lang = 'en';
  const languageButtons = ['ko', 'en'].map(lang => element({ 'data-set-lang': lang }));
  const themeButtons = ['system', 'light', 'dark'].map(theme => element({ 'data-set-theme': theme }));
  const links = hrefs.map(href => ({ href: new URL(href, base).href }));
  const document = {
    documentElement: root,
    getElementById() { return null; },
    querySelectorAll(selector) {
      return { '[data-set-lang]': languageButtons, '[data-set-theme]': themeButtons, '[data-web-link]': links }[selector] || [];
    },
    addEventListener() {},
  };
  const location = { href: base + '?lang=en&theme=dark#unrelated' };
  const window = { location, history: { replaceState(_state, _unused, href) { location.href = href; } } };
  vm.runInNewContext(source, { document, window, navigator: {}, URL, console });
  function expectPreferences(lang, theme) {
    links.forEach((link, index) => {
      const url = new URL(link.href);
      assert.equal(url.pathname, new URL('./web/', base).pathname);
      assert.equal(url.origin, new URL(base).origin);
      assert.equal(url.searchParams.get('lang'), lang);
      assert.equal(url.searchParams.get('theme'), theme);
      assert.equal(url.searchParams.get('mode'), hrefs[index].includes('mode=portal') ? 'portal' : null);
      assert.equal(url.hash, '', 'landing fragments must not leak into the web app');
      assert.deepEqual([...url.searchParams.keys()].sort(), theme ?
        (hrefs[index].includes('mode=portal') ? ['lang', 'mode', 'theme'] : ['lang', 'theme']) :
        (hrefs[index].includes('mode=portal') ? ['lang', 'mode'] : ['lang']));
    });
  }
  expectPreferences('en', 'dark');
  languageButtons[0].listeners.click();
  expectPreferences('ko', 'dark');
  themeButtons[1].listeners.click();
  expectPreferences('ko', 'light');
  themeButtons[0].listeners.click();
  expectPreferences('ko', null);
  languageButtons[1].listeners.click();
  expectPreferences('en', null);
}
console.log('landing web: local assets, native portal distinction and language/theme navigation passed');
