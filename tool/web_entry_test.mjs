import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { entryTarget } from '../docs/web/entry.mjs';

for (const base of ['https://example.test/Intragram/web/', 'http://localhost:8765/web/index.html']) {
  const original = new URL(base);
  const target = entryTarget(base + '?lang=ko&theme=dark&mode=portal&code=SECRET&token=SECRET#t=SECRET');
  assert.equal(target.origin, original.origin);
  assert.equal(target.pathname, new URL('./app/', base).pathname);
  assert.equal(target.search, '?lang=ko&theme=dark&mode=portal');
  assert.equal(target.hash, ''); assert.ok(!target.href.includes('SECRET'));
  assert.equal(entryTarget(base + '?lang=unknown&theme=javascript&mode=https://evil.test').search, '');
  assert.equal(entryTarget(base + '?lang=en&theme=system').search, '?lang=en&theme=system');
  const links = { 'open-app': {}, 'open-lite': {} };
  let redirected;
  const window = { location: { href: base + '?lang=en&theme=light&mode=portal&token=SECRET#t=SECRET', replace(href) { redirected = href; } } };
  const source = readFileSync(new URL('../docs/web/entry.mjs', import.meta.url), 'utf8').replace('export function ', 'function ');
  vm.runInNewContext(source, { URL, window, document: { getElementById(id) { return links[id]; } } });
  assert.equal(redirected, links['open-app'].href);
  assert.equal(new URL(redirected).pathname, new URL('./app/', base).pathname);
  assert.equal(new URL(links['open-lite'].href).pathname, new URL('./lite.html', base).pathname);
  for (const href of [redirected, links['open-lite'].href]) {
    assert.equal(new URL(href).search, '?lang=en&theme=light&mode=portal');
    assert.equal(new URL(href).hash, '');
    assert.ok(!href.includes('SECRET'));
  }
}
const bootstrap = readFileSync(new URL('../web/flutter_bootstrap.js', import.meta.url), 'utf8')
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');
const symbols = readFileSync(new URL('../web/assets/fonts/fallback/notosanssymbols/v43/rP2up3q65FkAtHfwd-eIS2brbDN6gxP34F9jRRCe4W3gfQ8gb_VFRkzrbQ.woff2', import.meta.url));
assert.equal(symbols.toString('ascii', 0, 4), 'wOF2', 'bundle the local Flutter symbol fallback');
assert.match(readFileSync(new URL('../assets/fonts/OFL-NotoSansSymbols.txt', import.meta.url), 'utf8'), /SIL OPEN FONT LICENSE/);
for (const theme of ['light', 'dark', 'system', 'invalid']) {
  let firstFrame, removed = false;
  const document = { documentElement: { dataset: {} }, getElementById(id) { assert.equal(id, 'app-loading'); return { remove() { removed = true; } }; } };
  const window = { location: { search: '?theme=' + theme }, addEventListener(name, action, options) { assert.equal(name, 'flutter-first-frame'); assert.equal(options.once, true); firstFrame = action; } };
  vm.runInNewContext(bootstrap, { URLSearchParams, window, document, _flutter: { loader: { load(config) {
    assert.equal(typeof firstFrame, 'function', 'listen before Flutter can draw its first frame');
    assert.equal(removed, false, 'retain the loading view until Flutter draws');
    assert.equal(config.config.canvasKitBaseUrl, 'canvaskit/');
  } } } });
  assert.equal(document.documentElement.dataset.theme, ['light', 'dark'].includes(theme) ? theme : undefined);
  firstFrame();
  assert.equal(removed, true);
}
// 다른 페이지의 프레임 안이면 앱을 띄우지 않고 새 탭 링크만 보여 줌
{
  let loaded = false, ringRemoved = false;
  const shown = [];
  const loading = { querySelector: selector => selector === '.loading-ring'
    ? { remove() { ringRemoved = true; } }
    : { replaceChildren(...nodes) { shown.push(...nodes); } } };
  const document = { documentElement: { dataset: {} }, getElementById: () => loading, createElement: tag => ({ tag }) };
  const window = { top: {}, self: {}, location: { search: '', href: 'https://example.test/Intragram/web/app/?lang=ko' },
    addEventListener() { assert.fail('no first-frame listener inside a frame'); } };
  vm.runInNewContext(bootstrap, { URLSearchParams, window, document, _flutter: { loader: { load() { loaded = true; } } } });
  assert.equal(loaded, false, 'never start the app inside a frame');
  assert.equal(ringRemoved, true);
  const link = shown.find(node => node?.tag === 'a');
  assert.deepEqual([link?.href, link?.target, link?.rel], ['https://example.test/Intragram/web/app/?lang=ko', '_blank', 'noopener noreferrer']);
}
console.log('web entry: local target, project paths, preference whitelist, secret stripping, loading first-frame lifecycle and frame refusal passed');
