/**
 * Config-summary chevron ↔ collapse state sync (source-level guard).
 *
 * The chevron rotation CSS keys off #config-summary[aria-expanded], but
 * Bootstrap only maintains aria-expanded on togglers that carried
 * data-bs-toggle when the Collapse instance was FIRST created —
 * #config-summary gains data-bs-toggle only after a session starts, so the
 * cached instance's trigger list is empty and Bootstrap never updates it.
 * monadic.js therefore drives aria-expanded from the collapse events itself.
 *
 * monadic.js attaches top-level DOM listeners and cannot be require()d under
 * jsdom, so this guard asserts the wiring exists in the source (same approach
 * as setparams-library-rag.test.js).
 */

const fs = require('fs');
const path = require('path');

const SOURCE = fs.readFileSync(
  path.resolve(__dirname, '../../docker/services/ruby/public/js/monadic.js'),
  'utf8'
);

describe('config-summary chevron sync wiring in monadic.js', () => {
  it('listens for show.bs.collapse and sets aria-expanded="true"', () => {
    const m = SOURCE.match(/addEventListener\("show\.bs\.collapse"[\s\S]{0,400}?aria-expanded",\s*"true"/);
    expect(m).not.toBeNull();
  });

  it('listens for hide.bs.collapse and sets aria-expanded="false"', () => {
    const m = SOURCE.match(/addEventListener\("hide\.bs\.collapse"[\s\S]{0,400}?aria-expanded",\s*"false"/);
    expect(m).not.toBeNull();
  });

  it('guards against bubbled events from nested collapses (e.target check)', () => {
    const showBlock = SOURCE.match(/addEventListener\("show\.bs\.collapse"[\s\S]{0,200}/)[0];
    const hideBlock = SOURCE.match(/addEventListener\("hide\.bs\.collapse"[\s\S]{0,200}/)[0];
    expect(showBlock).toMatch(/e\.target !== configBody/);
    expect(hideBlock).toMatch(/e\.target !== configBody/);
  });
});
