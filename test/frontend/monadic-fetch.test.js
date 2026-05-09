/**
 * Tests for monadic-fetch.js
 *
 * The wrapper exists to enforce the X-Requested-With contract that the
 * Sinatra `request.xhr?` branching depends on. The lint:xhr_pair rule
 * checks the source for the literal header; these tests check the
 * runtime behaviour so a regression in the wrapper itself is also
 * caught.
 */

require('../../docker/services/ruby/public/js/monadic/monadic-fetch.js');
const monadicFetch = window.monadicFetch;

describe('monadicFetch', () => {
  let fetchSpy;

  beforeEach(() => {
    // jsdom does not always expose a fetch on globalThis; provide one
    // so the mock attaches to the same property the wrapper calls.
    if (typeof global.fetch !== 'function') {
      global.fetch = jest.fn();
    }
    fetchSpy = jest.spyOn(global, 'fetch');
  });

  afterEach(() => {
    if (fetchSpy && typeof fetchSpy.mockRestore === 'function') {
      fetchSpy.mockRestore();
    }
  });

  // Minimal Response shim so the tests do not depend on jsdom exposing
  // the full Fetch API constructors. The wrapper only uses
  // status / ok / statusText / headers.get / text(); anything beyond that
  // is out of scope.
  function makeResponse({ body, status = 200, statusText = 'OK', contentType = 'application/json' }) {
    return {
      status,
      statusText,
      ok: status >= 200 && status < 300,
      headers: {
        get(name) {
          return name.toLowerCase() === 'content-type' ? contentType : null;
        }
      },
      text: () => Promise.resolve(typeof body === 'string' ? body : JSON.stringify(body))
    };
  }

  function jsonResponse(body, init = {}) {
    return makeResponse({ body, status: init.status, statusText: init.statusText });
  }

  describe('postJson', () => {
    it('always sends X-Requested-With for FormData uploads', async () => {
      fetchSpy.mockResolvedValue(jsonResponse({ ok: true }));
      const fd = new FormData();
      fd.append('foo', 'bar');

      await monadicFetch.postJson('/document', fd);

      expect(fetchSpy).toHaveBeenCalledTimes(1);
      const init = fetchSpy.mock.calls[0][1];
      expect(init.headers['X-Requested-With']).toBe('XMLHttpRequest');
      expect(init.body).toBe(fd);
      expect(init.method).toBe('POST');
    });

    it('serialises plain objects as JSON with Content-Type', async () => {
      fetchSpy.mockResolvedValue(jsonResponse({ ok: true }));
      await monadicFetch.postJson('/api/foo', { a: 1, b: [2, 3] });

      const init = fetchSpy.mock.calls[0][1];
      expect(init.headers['Content-Type']).toBe('application/json');
      expect(init.headers['X-Requested-With']).toBe('XMLHttpRequest');
      expect(JSON.parse(init.body)).toEqual({ a: 1, b: [2, 3] });
    });

    it('returns parsed JSON on success', async () => {
      fetchSpy.mockResolvedValue(jsonResponse({ success: true, content: 'hello' }));
      const data = await monadicFetch.postJson('/document', new FormData());
      expect(data).toEqual({ success: true, content: 'hello' });
    });

    it('throws a structured error when the server returns a non-2xx status', async () => {
      fetchSpy.mockResolvedValue(jsonResponse({ error: 'nope' }, { status: 500, statusText: 'Internal Server Error' }));
      await expect(monadicFetch.postJson('/api/foo', { a: 1 })).rejects.toMatchObject({
        status: 500,
        body: { error: 'nope' }
      });
    });

    it('throws a typed error when the response body is not parseable JSON', async () => {
      // The exact failure mode that produced the audit's
      // "No number after minus sign" defect: server claims JSON but
      // body is plain markdown.
      fetchSpy.mockResolvedValue(makeResponse({
        body: "\n---\nplain markdown",
        contentType: 'application/json'
      }));
      await expect(monadicFetch.postJson('/document', new FormData())).rejects.toMatchObject({
        status: 200,
        body: expect.stringContaining('---')
      });
    });

    it('returns the raw text body when Content-Type is not JSON (graceful fallback)', async () => {
      fetchSpy.mockResolvedValue(makeResponse({ body: 'plain', contentType: 'text/plain' }));
      const data = await monadicFetch.postJson('/api/text', new FormData());
      expect(data).toBe('plain');
    });
  });

  describe('getJson', () => {
    it('always sends X-Requested-With', async () => {
      fetchSpy.mockResolvedValue(jsonResponse({ ok: true }));
      await monadicFetch.getJson('/api/status');

      const init = fetchSpy.mock.calls[0][1];
      expect(init.method).toBe('GET');
      expect(init.headers['X-Requested-With']).toBe('XMLHttpRequest');
    });
  });
});
