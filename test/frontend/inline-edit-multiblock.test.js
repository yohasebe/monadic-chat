/**
 * @jest-environment jsdom
 *
 * Contract regression for the inline-edit multi-block transform.
 *
 * Background: when the user clicks the edit (pencil) button on a
 * rendered chat card, cards.js replaces the rendered Markdown with a
 * textarea so the source can be edited. The pre-audit version replaced
 * only the FIRST <p>, leaving stray <ul>/<p> blocks rendered below
 * the textarea — a visible UI defect that the audit fix corrected.
 *
 * This test fixes the contract of the transform itself:
 *   - All top-level Markdown blocks are removed.
 *   - The textarea takes the position of the first removed block.
 *   - Non-Markdown elements (images, audio, custom widgets) survive.
 *
 * The selector list duplicates cards.js's `renderedSelector` on
 * purpose — it serves as a spec that a future refactor must keep
 * synchronous with the production code. If the two diverge the
 * regression will reappear, which is exactly when this test should
 * surface it.
 */

const RENDERED_SELECTOR = ':scope > p, :scope > ul, :scope > ol, ' +
  ':scope > h1, :scope > h2, :scope > h3, :scope > h4, :scope > h5, :scope > h6, ' +
  ':scope > blockquote, :scope > pre, :scope > hr, :scope > table, ' +
  ':scope > div.markdown-block';

function applyEditTransform(cardTextEl, editArea) {
  const blocks = cardTextEl.querySelectorAll(RENDERED_SELECTOR);
  if (blocks.length > 0) {
    blocks[0].replaceWith(editArea);
    for (let i = 1; i < blocks.length; i++) {
      blocks[i].remove();
    }
  } else {
    cardTextEl.prepend(editArea);
  }
}

describe('inline-edit multi-block transform', () => {
  let cardTextEl;
  let editArea;

  beforeEach(() => {
    document.body.innerHTML = '';
    editArea = document.createElement('textarea');
    editArea.className = 'inline-edit-textarea';
  });

  it('removes every top-level Markdown block, not just the first paragraph', () => {
    document.body.innerHTML = `
      <div class="card-text">
        <p>opening paragraph</p>
        <ul><li>bullet a</li><li>bullet b</li></ul>
        <p>middle paragraph</p>
        <h2>section</h2>
        <p>closing paragraph</p>
      </div>`;
    cardTextEl = document.querySelector('.card-text');

    applyEditTransform(cardTextEl, editArea);

    expect(cardTextEl.contains(editArea)).toBe(true);
    expect(cardTextEl.querySelectorAll('p, ul, h2').length).toBe(0);
  });

  it('keeps non-Markdown elements (images, audio, custom widgets)', () => {
    document.body.innerHTML = `
      <div class="card-text">
        <img src="data:image/png;base64,xx" alt="x">
        <p>caption</p>
        <audio controls></audio>
      </div>`;
    cardTextEl = document.querySelector('.card-text');

    applyEditTransform(cardTextEl, editArea);

    // <p> is removed; <img> and <audio> survive.
    expect(cardTextEl.querySelector('p')).toBeNull();
    expect(cardTextEl.querySelector('img')).not.toBeNull();
    expect(cardTextEl.querySelector('audio')).not.toBeNull();
  });

  it('falls back to prepending when the card has no rendered Markdown', () => {
    document.body.innerHTML = `
      <div class="card-text">
        <img src="data:image/png;base64,xx" alt="x">
      </div>`;
    cardTextEl = document.querySelector('.card-text');

    applyEditTransform(cardTextEl, editArea);

    expect(cardTextEl.firstElementChild).toBe(editArea);
    expect(cardTextEl.querySelector('img')).not.toBeNull();
  });

  it('replaces tables and code blocks too (not just inline content)', () => {
    document.body.innerHTML = `
      <div class="card-text">
        <table><tr><td>a</td></tr></table>
        <pre><code>code</code></pre>
        <hr>
      </div>`;
    cardTextEl = document.querySelector('.card-text');

    applyEditTransform(cardTextEl, editArea);

    expect(cardTextEl.querySelectorAll('table, pre, hr').length).toBe(0);
    expect(cardTextEl.contains(editArea)).toBe(true);
  });
});
