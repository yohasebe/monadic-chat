// The app window adds its policy to the responses of the app's server and
// keeps the policy the server sent: every policy of a response applies, so
// a response the server locked down (a worker that may load nothing, a file
// served in a sandbox) stays as the server made it.
const fs = require('fs');
const path = require('path');
// Node's own URL: test/setup.js replaces the global one with a stub.
const { URL: NodeURL } = require('url');

const MAIN = fs.readFileSync(path.join(__dirname, '../../app/main.js'), 'utf8');

// withAppPolicy as main.js defines it, with what it uses.
function load() {
  const parts = [
    /^const allowedLocalHosts = new Set\(\[[^\]]*\]\);$/m,
    /^function isAppUrl\(value\) \{\n[\s\S]*?\n\}$/m,
    /^const APP_CSP = \[[\s\S]*?\]\.join\('; '\);$/m,
    /^function withAppPolicy\(headers, url\) \{\n[\s\S]*?\n\}$/m
  ].map((re) => {
    const found = MAIN.match(re);
    expect(found).not.toBeNull();
    return found[0];
  });
  return new Function('URL', `${parts.join('\n')}\nreturn { withAppPolicy, APP_CSP };`)(NodeURL);
}

describe('the app window\'s policy on its server\'s responses', () => {
  const { withAppPolicy, APP_CSP } = load();
  const APP = 'http://localhost:4567/vendor/vega/vega-worker.mjs';

  test('keeps the policy the server sent, in any spelling, beside the app\'s', () => {
    const out = withAppPolicy({ 'content-type': ['text/javascript'], 'content-security-policy': ["default-src 'none'"] }, APP);
    expect(out['Content-Security-Policy']).toEqual(["default-src 'none'", APP_CSP]);
    expect(out['content-type']).toEqual(['text/javascript']);
    expect(Object.keys(out).filter((k) => k.toLowerCase() === 'content-security-policy')).toEqual(['Content-Security-Policy']);
    const two = withAppPolicy({ 'Content-Security-Policy': ['sandbox', "frame-ancestors 'self'"], 'CONTENT-SECURITY-POLICY': 'a' }, APP);
    expect(two['Content-Security-Policy']).toEqual(['sandbox', "frame-ancestors 'self'", 'a', APP_CSP]);
  });

  test('gives a response without a policy the app\'s alone', () => {
    expect(withAppPolicy({ 'content-type': ['text/html'] }, 'http://127.0.0.1:4567/')['Content-Security-Policy']).toEqual([APP_CSP]);
    expect(withAppPolicy(undefined, 'http://127.0.0.1:4567/')['Content-Security-Policy']).toEqual([APP_CSP]);
  });

  test('leaves the responses of other hosts as they are', () => {
    const headers = { 'content-security-policy': ['x'] };
    expect(withAppPolicy(headers, 'http://localhost:8080/')).toBe(headers);
    expect(withAppPolicy(headers, 'https://example.com/')).toBe(headers);
  });

  test('is what the window applies to every response of the app\'s server', () => {
    expect(MAIN).toMatch(/onHeadersReceived\([\s\S]*?withAppPolicy\(details\.responseHeaders, details\.url\)/);
    expect(MAIN).not.toMatch(/delete responseHeaders\[['"]content-security-policy['"]\]/i);
  });
});
