// The page asks the server to check its key, and sends none of its own: a
// field added later must not carry a key from the page to the server.
const fs = require('fs');
const path = require('path');

const SOURCE = fs.readFileSync(path.join(__dirname, '../../docker/services/ruby/public/js/monadic/websocket.js'), 'utf8');

describe('CHECK_TOKEN request', () => {
  test('carries no key from the page', () => {
    const sends = SOURCE.match(/safeWsSend\(\{\s*message:\s*"CHECK_TOKEN"[\s\S]*?\}\s*,/g) || [];
    expect(sends.length).toBeGreaterThan(0);
    for (const send of sends) {
      expect(send).not.toMatch(/\bcontents\b|\$id\(|\.value/);
    }
  });

  test('no page script reads a key field', () => {
    const dir = path.join(__dirname, '../../docker/services/ruby/public/js/monadic');
    const offenders = fs.readdirSync(dir).filter((f) => f.endsWith('.js'))
      .filter((f) => /\$id\(\s*["'](?:api-token|token)["']\s*\)/.test(fs.readFileSync(path.join(dir, f), 'utf8')));
    expect(offenders).toEqual([]);
  });
});
