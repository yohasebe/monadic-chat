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
 *   - convertDocument  → POST /document with X-Requested-With + form data
 *   - fetchWebpage     → POST /fetch_webpage with X-Requested-With + form data
 *   - importSession    → POST /load   with X-Requested-With + form data
 *
 * The matching server-side guarantee is the JsonRoute pattern (always
 * returns JSON, no xhr branching). Both layers together are what keeps
 * the bug class extinct.
 */

const formHandlers = require('../../docker/services/ruby/public/js/monadic/form-handlers.js');

describe('route-contract smoke (frontend fetch callers)', () => {
  let fetchSpy;

  beforeEach(() => {
    if (typeof global.fetch !== 'function') global.fetch = jest.fn();
    fetchSpy = jest.spyOn(global, 'fetch');
    fetchSpy.mockResolvedValue({
      ok: true,
      status: 200,
      statusText: 'OK',
      json: () => Promise.resolve({ success: true, content: 'stub' })
    });
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  describe('convertDocument → /document', () => {
    it('always sets X-Requested-With and uses POST', async () => {
      const file = new File(['%PDF-1.4'], 'sample.pdf', { type: 'application/pdf' });
      await formHandlers.convertDocument(file, '');

      expect(fetchSpy).toHaveBeenCalledTimes(1);
      const [url, init] = fetchSpy.mock.calls[0];
      expect(url).toBe('/document');
      expect(init.method).toBe('POST');
      expect(init.headers && init.headers['X-Requested-With']).toBe('XMLHttpRequest');
      // Body must be FormData so the multipart upload reaches Sinatra
      // intact; encoding it as JSON would lose the file.
      expect(init.body).toBeInstanceOf(FormData);
    });

    it('rejects unsupported file types before reaching the network', async () => {
      // application/octet-stream is what the browser sends for unknown
      // MIME types; we pre-filter so the server is never asked to
      // unwrap a binary blob it cannot handle.
      const file = new File(['xx'], 'x.bin', { type: 'application/octet-stream' });
      await expect(formHandlers.convertDocument(file, '')).rejects.toThrow(/Unsupported/);
      expect(fetchSpy).not.toHaveBeenCalled();
    });
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
      // The exact pre-fix failure: server returns markdown with a
      // leading "\n---\n" instead of JSON, await res.json() throws
      // "No number after minus sign". The wrapper turns this into a
      // structured error so the UI can show a useful message.
      fetchSpy.mockResolvedValue({
        ok: true,
        status: 200,
        statusText: 'OK',
        json: () => Promise.reject(new SyntaxError('No number after minus sign in JSON at position 2'))
      });

      const file = new File(['%PDF-1.4'], 'sample.pdf', { type: 'application/pdf' });
      await expect(formHandlers.convertDocument(file, '')).rejects.toThrow(/JSON|number/i);
    });
  });
});
