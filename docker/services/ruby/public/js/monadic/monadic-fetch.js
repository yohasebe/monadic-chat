/**
 * monadicFetch — small wrapper around fetch() that enforces the
 * project's contract with Sinatra routes.
 *
 * Background: several Sinatra routes branch on `request.xhr?` and only
 * return JSON for AJAX-style requests. The browser's native fetch()
 * does not attach the `X-Requested-With: XMLHttpRequest` header, so
 * those routes silently fall through to a non-JSON code path. The
 * audit that produced docs_dev/architecture_hardening_plan.md found
 * three callsites where this defect had reached users (Text from file,
 * Text from URL, Library import).
 *
 * monadicFetch.postJson always sends the X-Requested-With header so a
 * dropped header cannot reintroduce the defect class. The matching
 * server-side rule is the `lint:xhr_pair` anti-pattern check in CI.
 *
 * Usage:
 *   const data = await monadicFetch.postJson('/document', formData);
 *   // → returns parsed JSON, throws { status, body, message } on failure
 *
 *   const data = await monadicFetch.postJson('/api/foo', { a: 1 });
 *   // → JSON.stringify'd body, Content-Type: application/json
 *
 *   const data = await monadicFetch.getJson('/api/status');
 */
(function (window) {
  'use strict';

  const REQUESTED_WITH = { 'X-Requested-With': 'XMLHttpRequest' };

  function buildBody(body) {
    if (body == null) return { body: undefined, headers: {} };
    if (body instanceof FormData) return { body, headers: {} };
    if (typeof body === 'string') {
      return { body, headers: { 'Content-Type': 'text/plain;charset=UTF-8' } };
    }
    // Plain object → JSON
    return {
      body: JSON.stringify(body),
      headers: { 'Content-Type': 'application/json' }
    };
  }

  async function parseResponse(response) {
    const contentType = response.headers.get('content-type') || '';
    const raw = await response.text();
    if (contentType.includes('application/json')) {
      try {
        return JSON.parse(raw);
      } catch (err) {
        const error = new Error(
          `Server returned a Content-Type of ${contentType} but the body was not valid JSON.`
        );
        error.status = response.status;
        error.body = raw;
        error.cause = err;
        throw error;
      }
    }
    return raw;
  }

  async function request(url, init) {
    const headers = Object.assign({}, REQUESTED_WITH, init.headers || {});
    const opts = Object.assign({}, init, { headers });

    let response;
    try {
      response = await fetch(url, opts);
    } catch (networkError) {
      const error = new Error(`Network error contacting ${url}: ${networkError.message}`);
      error.cause = networkError;
      throw error;
    }

    const data = await parseResponse(response);

    if (!response.ok) {
      const error = new Error(
        `Request to ${url} failed: ${response.status} ${response.statusText}`
      );
      error.status = response.status;
      error.body = data;
      throw error;
    }
    return data;
  }

  /**
   * POST to a route that returns JSON. Body may be FormData (uploads),
   * a string (raw), a plain object (JSON-encoded), or undefined.
   * Always includes the X-Requested-With contract header.
   */
  function postJson(url, body, options = {}) {
    const built = buildBody(body);
    return request(url, {
      method: 'POST',
      body: built.body,
      headers: Object.assign({}, built.headers, options.headers || {}),
      signal: options.signal
    });
  }

  /** GET a JSON resource. */
  function getJson(url, options = {}) {
    return request(url, {
      method: 'GET',
      headers: options.headers || {},
      signal: options.signal
    });
  }

  window.monadicFetch = { postJson, getJson, _request: request };
})(window);
