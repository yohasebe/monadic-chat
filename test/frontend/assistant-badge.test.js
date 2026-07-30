/**
 * @jest-environment jsdom
 */

/**
 * The assistant card's role label.
 *
 * This file exists because of a specific failure. The "interrupted" marker
 * was first added inline in ws-html-handler.js's `_handleAssistantRole`, and
 * a test there passed — but that function is the FALLBACK, reached only when
 * `wsHandlers.handleHtmlMessage` declines the message. Assistant messages
 * never decline, so the live path (websocket-handlers.js) and the session
 * restore path (monadic.js) both kept their own hardcoded copies of the badge
 * and the marker never rendered in the product.
 *
 * The markup now lives in one place. These tests cover that one place, and
 * a companion assertion checks that the call sites actually use it rather
 * than reintroducing a copy.
 */

const fs = require('fs');
const path = require('path');

const { assistantBadge } = require('../../docker/services/ruby/public/js/monadic/card-renderer');

const read = (rel) => fs.readFileSync(path.resolve(__dirname, '../..', rel), 'utf8');

beforeEach(() => {
  window.escapeHtml = (s) => String(s);
});

afterEach(() => {
  delete window.escapeHtml;
  delete global.webUIi18n;
});

describe('assistantBadge', () => {
  it('labels an ordinary assistant card', () => {
    const badge = assistantBadge({ role: 'assistant', text: 'hi' });

    expect(badge).toContain('Assistant');
    expect(badge).not.toMatch(/interrupted/i);
  });

  it('marks a card the server flagged as interrupted', () => {
    const badge = assistantBadge({ role: 'assistant', text: 'partial', interrupted: true });

    expect(badge).toContain('Assistant');
    expect(badge).toMatch(/interrupted/i);
  });

  it('tolerates a missing content hash', () => {
    expect(() => assistantBadge()).not.toThrow();
    expect(assistantBadge()).toContain('Assistant');
  });

  it('uses the translated label when i18n is available', () => {
    global.webUIi18n = { t: jest.fn().mockReturnValue('中断されました') };

    const badge = assistantBadge({ interrupted: true });

    expect(global.webUIi18n.t).toHaveBeenCalledWith('ui.messages.responseInterrupted');
    expect(badge).toContain('中断されました');
  });

  it('falls back to English when i18n is absent', () => {
    expect(assistantBadge({ interrupted: true })).toContain('Interrupted');
  });
});

/**
 * Source-level guard against the copy coming back.
 *
 * Behavioural tests cannot catch a call site that stops calling the helper —
 * that is exactly how the marker went missing the first time.
 */
describe('call sites use the shared badge', () => {
  const sites = {
    'websocket-handlers.js (live path)': 'docker/services/ruby/public/js/monadic/websocket-handlers.js',
    'ws-html-handler.js (fallback path)': 'docker/services/ruby/public/js/monadic/ws-html-handler.js',
    'monadic.js (session restore)': 'docker/services/ruby/public/js/monadic.js'
  };

  // Only final-card creation is guarded. The streaming placeholder
  // (#temp-card) also carries an "Assistant" label but is replaced by the
  // final card, and a turn cannot be reported as interrupted while it is
  // still streaming — so its markup stays inline on purpose.
  const literalBadgeArg = /(?:createCardFunc|createCard|appendCard)\(\s*["']assistant["']\s*,\s*["'`]/;

  Object.entries(sites).forEach(([label, rel]) => {
    it(label, () => {
      const src = read(rel);

      expect(src).toContain('assistantBadge');
      expect(src).not.toMatch(literalBadgeArg);
    });
  });

  it('the guard would catch a reintroduced literal', () => {
    // Sanity-check the regex itself: a source-level assertion that cannot
    // fail is worse than no assertion.
    expect(`createCardFunc('assistant', '<span>Assistant</span>', html)`).toMatch(literalBadgeArg);
    expect(`createCardFunc('assistant', window.assistantBadge(c), html)`).not.toMatch(literalBadgeArg);
  });
});
