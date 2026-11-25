/**
 * Route-contract smoke tests for fetch callers that talk to xhr-aware
 * Sinatra routes.
 *
 * These tests exist because the original "Text from file" defect lived
 * exactly at the seam between frontend fetch() and the server's
 * `request.xhr?` gate. Static lint (lint:xhr_pair) already prevents a
 * fetch caller from being added without the X-Requested-With header,
 * but the lint cannot prove the *behaviour* still holds at runtime —
 * for example, if a future refactor moves the header into a wrapper
 * that ends up disabled by some other condition. This jest spec
 * pretends to be the network and verifies the actual outgoing request
 * shape.
 *
 * Coverage:
 *   - fetchWebpage     → POST /fetch_webpage with X-Requested-With + form data
 *   - importSession    → POST /load   with X-Requested-With + form data
 *
 * The matching server-side guarantee is the JsonRoute pattern (always
 * returns JSON, no xhr branching). Both layers together are what keeps
 * the bug class extinct.
 */

// monadic-fetch must load first so window.monadicFetch is available
// when form-handlers calls it.
require('../../docker/services/ruby/public/js/monadic/monadic-fetch.js');
const formHandlers = require('../../docker/services/ruby/public/js/monadic/form-handlers.js');

describe('route-contract smoke (frontend fetch callers)', () => {
  let fetchSpy;

  beforeEach(() => {
    if (typeof global.fetch !== 'function') global.fetch = jest.fn();
    fetchSpy = jest.spyOn(global, 'fetch');
    fetchSpy.mockResolvedValue(makeJsonResponse({ success: true, content: 'stub' }));
  });

  // Minimal Response shim that matches the surface monadicFetch reads
  // (headers.get + text(); ok and status come from the spec object).
  function makeJsonResponse(body, { status = 200, statusText = 'OK' } = {}) {
    return {
      ok: status >= 200 && status < 300,
      status,
      statusText,
      headers: {
        get(name) {
          return name.toLowerCase() === 'content-type' ? 'application/json' : null;
        }
      },
      text: () => Promise.resolve(JSON.stringify(body)),
      json: () => Promise.resolve(body)
    };
  }

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  describe('fetchWebpage → /fetch_webpage', () => {
    it('always sets X-Requested-With and uses POST', async () => {
      await formHandlers.fetchWebpage('https://example.com/article', '');

      const [url, init] = fetchSpy.mock.calls[0];
      expect(url).toBe('/fetch_webpage');
      expect(init.method).toBe('POST');
      expect(init.headers['X-Requested-With']).toBe('XMLHttpRequest');
    });

    it('rejects non-http(s) URLs before reaching the network', async () => {
      // The server now also enforces this, but the pre-flight reduces
      // round-trip noise and keeps the URL out of the request log on
      // typo-class mistakes.
      await expect(formHandlers.fetchWebpage('javascript:alert(1)', '')).rejects.toThrow(/valid URL/);
      expect(fetchSpy).not.toHaveBeenCalled();
    });
  });

  describe('importSession → /load', () => {
    it('always sets X-Requested-With and uses POST', async () => {
      const file = new File(['{}'], 'session.json', { type: 'application/json' });
      // postLoadWithPassphraseRetry is also exported; importSession is
      // the public callsite the rest of the UI uses.
      await formHandlers.importSession(file);

      const [url, init] = fetchSpy.mock.calls[0];
      expect(url).toBe('/load');
      expect(init.method).toBe('POST');
      expect(init.headers['X-Requested-With']).toBe('XMLHttpRequest');
    });
  });

  describe('regression: JSON-parse failure surfaces a structured error', () => {
    it('does not silently swallow a non-JSON body when /document misbehaves', async () => {
      // The exact pre-fix failure: server claims JSON but body is
      // plain markdown. monadicFetch turns this into a structured
      // error rather than letting JSON.parse blow up downstream.
      fetchSpy.mockResolvedValue({
        ok: true, status: 200, statusText: 'OK',
        headers: { get: (n) => n.toLowerCase() === 'content-type' ? 'application/json' : null },
        text: () => Promise.resolve("\n---\nplain markdown"),
        json: () => Promise.reject(new SyntaxError('No number after minus sign'))
      });

      await expect(formHandlers.fetchWebpage('https://example.com/article', '')).rejects.toMatchObject({
        status: 200
      });
    });
  });
});
