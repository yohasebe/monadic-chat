/**
 * @jest-environment jsdom
 */

/**
 * §38d: a rejected LazyLoader promise must not veto retries forever.
 * With no CDN fallback (maxgraph), a cached rejection was a permanent
 * dead end — the viewer stayed an empty frame with no way forward.
 */

const fs = require('fs');
const path = require('path');

function loadLazyLoader() {
  const filePath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/lazy-loader.js');
  eval(fs.readFileSync(filePath, 'utf8'));
}

describe('LazyLoader failure eviction (§38d)', () => {
  beforeEach(() => {
    document.head.innerHTML = '';
    delete window.LazyLoader;
    delete window.maxgraph;
  });

  it('evicts a rejected load so the next call retries instead of reusing it', async () => {
    loadLazyLoader();
    const p1 = window.LazyLoader.maxgraph();
    // jsdom does not execute scripts: fail the local load, then the
    // (empty) CDN fallback.
    let scripts = document.head.querySelectorAll('script');
    expect(scripts.length).toBe(1);
    scripts[0].onerror();
    scripts = document.head.querySelectorAll('script');
    expect(scripts.length).toBe(2);
    scripts[1].onerror();
    await expect(p1).rejects.toThrow(/Failed to load maxgraph/);

    // Let the eviction .catch run.
    await Promise.resolve();

    // The next call must append a NEW script (a real retry), not return
    // the dead cached promise.
    const p2 = window.LazyLoader.maxgraph();
    scripts = document.head.querySelectorAll('script');
    expect(scripts.length).toBe(3);

    window.maxgraph = {};
    scripts[2].onload();
    await expect(p2).resolves.toBeUndefined();
  });
});
