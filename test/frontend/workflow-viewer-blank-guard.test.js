/**
 * Workflow Viewer blank-view self-healing (source-level guard).
 *
 * The viewer intermittently rendered an EMPTY canvas: fits, view-state saves,
 * and restores that ran while the container was hidden/zero-size (collapsed
 * settings panel, mode switches, mid-animation) produced off-screen
 * transforms, and restoreViewState() re-applied them in preference to a
 * fresh fit — so the blank state was memorised per app and reproduced.
 *
 * The fix validates actual content visibility (viewShowsContent): blank
 * states are never saved, and a restored state that doesn't show content is
 * dropped so the caller falls back to fitGraphToContainer(). These
 * source-level assertions lock that protection (the module's internals are
 * not exported).
 */

const fs = require('fs');
const path = require('path');

const SOURCE = fs.readFileSync(
  path.resolve(__dirname, '../../docker/services/ruby/public/js/monadic/workflow-viewer.js'),
  'utf8'
);

describe('Workflow Viewer blank-view protection', () => {
  it('defines the viewShowsContent visibility validator', () => {
    expect(SOURCE).toMatch(/function viewShowsContent\(\)/);
    // Intersection test against the container viewport
    expect(SOURCE).toMatch(/b\.x < cw && b\.y < ch/);
  });

  it('saveViewState refuses to memorise a blank view', () => {
    const save = SOURCE.match(/function saveViewState\(\)[\s\S]{0,500}?\n  \}/)[0];
    expect(save).toMatch(/if \(!viewShowsContent\(\)\) return;/);
  });

  it('restoreViewState drops a stale state and reports failure for fit fallback', () => {
    const restore = SOURCE.match(/function restoreViewState\(\)[\s\S]{0,700}?\n  \}/)[0];
    expect(restore).toMatch(/if \(!viewShowsContent\(\)\)/);
    expect(restore).toMatch(/delete viewStates\[currentApp\]/);
    expect(restore).toMatch(/return false/);
  });

  it('the resize observer falls back to fit when restore fails', () => {
    expect(SOURCE).toMatch(/if \(!restoreViewState\(\)\) fitGraphToContainer\(\);/);
  });
});
