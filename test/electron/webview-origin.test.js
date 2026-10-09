// The app window must not vouch for pages it loads: the server trusts a
// request's Origin, so the window leaves that header as the page sent it,
// and only the app's own pages are shown in it.
const fs = require('fs');
const path = require('path');
// Node's own URL: test/setup.js replaces the global one with a stub.
const { URL: NodeURL } = require('url');

const MAIN = fs.readFileSync(path.join(__dirname, '../../app/main.js'), 'utf8');

// Run isAppUrl as main.js defines it, not a copy of its rule
function loadIsAppUrl() {
  const hosts = MAIN.match(/^const allowedLocalHosts = new Set\(\[[^\]]*\]\);$/m);
  const fn = MAIN.match(/^function isAppUrl\(value\) \{\n[\s\S]*?\n\}$/m);
  expect(hosts).not.toBeNull();
  expect(fn).not.toBeNull();
  return new Function('URL', `${hosts[0]}\n${fn[0]}\nreturn isAppUrl;`)(NodeURL);
}

describe('app window and request origins', () => {
  test('no request header rewriting sets Origin', () => {
    expect(MAIN).not.toMatch(/requestHeaders\[['"]Origin['"]\]\s*=/);
    expect(MAIN).not.toMatch(/requestHeaders\.Origin\s*=/);
  });

  test('isAppUrl accepts the app and nothing else', () => {
    const isAppUrl = loadIsAppUrl();
    for (const url of ['http://localhost:4567/', 'http://127.0.0.1:4567/data/x.png', 'http://LOCALHOST:4567/?a=1']) {
      expect([url, isAppUrl(url)]).toEqual([url, true]);
    }
    for (const url of [
      'https://localhost:4567/', 'http://localhost:8080/', 'http://evil.example/',
      'http://localhost.evil.example:4567/', 'file:///etc/hosts', 'javascript:alert(1)', 'not a url', ''
    ]) {
      expect([url, isAppUrl(url)]).toEqual([url, false]);
    }
  });

  test('the app window refuses to navigate or redirect elsewhere', () => {
    const body = MAIN.match(/function openWebViewWindow\(url, forceReload = false\) \{[\s\S]*?\n\}\n/);
    expect(body).not.toBeNull();
    expect(body[0]).toMatch(/on\('will-navigate',[\s\S]*?if \(!isAppUrl\(navUrl\)\) \{\s*event\.preventDefault\(\)/);
    expect(body[0]).toMatch(/on\('will-redirect',[\s\S]*?if \(!isAppUrl\(navUrl\)\) event\.preventDefault\(\)/);
  });
});
