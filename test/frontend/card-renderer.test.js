/**
 * @jest-environment jsdom
 *
 * Tests for card-renderer.js (escapeHtml + createCard)
 * Extracted from cards.js for modularity.
 */

// Minimal jQuery-like mock that actually parses HTML via jsdom
function createJQueryFromHtml(htmlString) {
  const div = document.createElement('div');
  div.innerHTML = htmlString.trim();
  const el = div.firstElementChild;

  const wrapper = {
    0: el,
    length: el ? 1 : 0,
    hasClass: (cls) => el ? el.classList.contains(cls) : false,
    attr: (name, value) => {
      if (!el) return undefined;
      if (value === undefined) return el.getAttribute(name);
      el.setAttribute(name, value);
      return wrapper;
    },
    find: (selector) => {
      if (!el) return createJQueryFromHtml('');
      const found = el.querySelectorAll(selector);
      if (found.length === 0) {
        return { length: 0, html: () => '', text: () => '', remove: () => {} };
      }
      const first = found[0];
      return {
        length: found.length,
        html: () => first.innerHTML,
        text: () => first.textContent,
        remove: () => { found.forEach(n => n.remove()); },
      };
    },
    tooltip: jest.fn().mockReturnThis(),
    remove: () => { if (el && el.parentNode) el.parentNode.removeChild(el); },
    on: jest.fn().mockReturnThis(),
    off: jest.fn().mockReturnThis(),
  };
  return wrapper;
}

// Install jQuery-like $ before loading the module
global.$ = jest.fn((arg) => {
  if (typeof arg === 'string') {
    // Selector query
    if (arg.startsWith('<')) {
      return createJQueryFromHtml(arg);
    }
    // DOM selector (e.g., "#mid-123")
    const found = document.querySelectorAll(arg);
    if (found.length === 0) {
      return { length: 0, remove: jest.fn(), find: jest.fn(() => ({ length: 0 })) };
    }
    const el = found[0];
    return {
      length: found.length,
      0: el,
      remove: () => { el.remove(); },
      find: (sel) => {
        const inner = el.querySelectorAll(sel);
        return { length: inner.length };
      },
    };
  }
  return { length: 0 };
});

// Runtime globals
global.getTranslation = jest.fn((key, fallback) => fallback);
global.runningOnChrome = true;
global.runningOnEdge = false;
global.runningOnSafari = false;
global.attachEventListeners = jest.fn();
global.detachEventListeners = jest.fn();
global.mids = new Set();
global.webUIi18n = { t: jest.fn(key => key) };
const realDateNow = Date.now;
global.Date.now = jest.fn().mockReturnValue(99999);

// Load module under test
const { escapeHtml, createCard } = require('../../docker/services/ruby/public/js/monadic/card-renderer');

afterAll(() => {
  global.Date.now = realDateNow;
});

describe('card-renderer', () => {
  beforeEach(() => {
    document.body.innerHTML = '<div id="discourse"></div>';
    global.mids = new Set();
    global.attachEventListeners.mockClear();
    global.detachEventListeners.mockClear();
    global.runningOnChrome = true;
    global.runningOnEdge = false;
    global.runningOnSafari = false;
  });

  // ── escapeHtml ──────────────────────────────────────────
  describe('escapeHtml', () => {
    it('escapes all 5 HTML-sensitive characters', () => {
      expect(escapeHtml('&<>"\''))
        .toBe('&amp;&lt;&gt;&quot;&#039;');
    });

    it('returns empty string for null/undefined', () => {
      expect(escapeHtml(null)).toBe('');
      expect(escapeHtml(undefined)).toBe('');
    });

    it('returns safe strings unchanged', () => {
      expect(escapeHtml('hello world')).toBe('hello world');
    });
  });

  // ── createCard ──────────────────────────────────────────
  describe('createCard', () => {
    const badge = '<span class="text-secondary"><i class="fas fa-face-smile"></i></span>';

    it('returns a card element with correct class', () => {
      const card = createCard('user', badge, 'Hello');
      expect(card.length).toBe(1);
      expect(card.hasClass('card')).toBe(true);
    });

    it('sets message ID on the card element', () => {
      const card = createCard('user', badge, 'Test', 'en', 'msg-123');
      expect(card.attr('id')).toBe('msg-123');
    });

    it('adds mid to mids Set', () => {
      createCard('user', badge, 'Test', 'en', 'mid-abc');
      expect(global.mids.has('mid-abc')).toBe(true);
    });

    it('does not add empty mid to mids', () => {
      createCard('user', badge, 'Test', 'en', '');
      expect(global.mids.size).toBe(0);
    });

    it('calls attachEventListeners on the new card', () => {
      createCard('assistant', badge, 'Response');
      expect(global.attachEventListeners).toHaveBeenCalled();
    });

    it('applies active status class when status=true', () => {
      const card = createCard('user', badge, 'Hi', 'en', 'mid-1', true);
      const html = card[0].outerHTML;
      expect(html).toContain('status active');
    });

    it('applies inactive status (no active class) when status=false', () => {
      const card = createCard('user', badge, 'Hi', 'en', 'mid-2', false);
      const html = card[0].outerHTML;
      // Should have 'status' class but NOT 'active'
      expect(html).toMatch(/class="status\s*"/);
    });

    it('adds cache-busting param to img src', () => {
      const card = createCard('assistant', badge, '<img src="http://x.com/a.png" />');
      const cardHtml = card.find('.card-text').html();
      expect(cardHtml).toContain('?dummy=99999');
    });

    it('adds target="_blank" to <a> tags', () => {
      const card = createCard('assistant', badge, '<a href="http://x.com">link</a>');
      const cardHtml = card.find('.card-text').html();
      expect(cardHtml).toContain('target="_blank"');
    });

    it('does not double-add target attribute', () => {
      const card = createCard('assistant', badge, '<a href="http://x.com" target="_self">link</a>');
      const cardHtml = card.find('.card-text').html();
      expect(cardHtml).toContain('target="_self"');
      expect(cardHtml).not.toContain('target="_blank"');
    });

    it('escapes plain-text system messages (no angle brackets)', () => {
      // createCard only escapes system messages that have NO < or > characters
      const card = createCard('system', badge, 'System prompt line1\nline2');
      const cardHtml = card.find('.card-text').html();
      expect(cardHtml).toContain('System prompt line1');
      expect(cardHtml).toContain('<br>');
    });

    it('preserves HTML in system messages containing tags', () => {
      const card = createCard('system', badge, '<b>bold</b>');
      const cardHtml = card.find('.card-text').html();
      expect(cardHtml).toContain('<b>bold</b>');
    });

    it('renders turn badge for user role', () => {
      const card = createCard('user', badge, 'Q', 'en', 'mid-t1', true, [], false, 3);
      const html = card[0].outerHTML;
      expect(html).toContain('T3');
      expect(html).toContain('data-turn="3"');
      expect(html).toContain('card-turn-badge-user');
    });

    it('renders turn badge for assistant role', () => {
      const card = createCard('assistant', badge, 'A', 'en', 'mid-t2', true, [], false, 5);
      const html = card[0].outerHTML;
      expect(html).toContain('T5');
      expect(html).toContain('card-turn-badge');
      // assistant badge should NOT have the user-specific class
      expect(html).not.toContain('card-turn-badge-user');
    });

    it('does not render turn badge when turnNumber is null', () => {
      const card = createCard('user', badge, 'Q', 'en', 'mid-nt', true, [], false, null);
      const html = card[0].outerHTML;
      expect(html).not.toContain('card-turn-badge');
    });

    it('renders image attachments', () => {
      const images = [
        { title: 'photo.png', data: 'data:image/png;base64,abc', type: 'image/png' }
      ];
      const card = createCard('user', badge, 'See image', 'en', 'mid-img', true, images);
      const cardHtml = card.find('.card-text').html();
      expect(cardHtml).toContain('base64-image');
      expect(cardHtml).toContain('photo.png');
    });

    it('renders PDF attachments', () => {
      const images = [
        { title: 'doc.pdf', data: '', type: 'application/pdf' }
      ];
      const card = createCard('user', badge, 'See PDF', 'en', 'mid-pdf', true, images);
      const cardHtml = card.find('.card-text').html();
      expect(cardHtml).toContain('pdf-preview');
      expect(cardHtml).toContain('doc.pdf');
    });

    it('renders mask overlay for paired images', () => {
      const images = [
        { title: 'photo.png', data: 'data:image/png;base64,abc', type: 'image/png' },
        { title: 'mask__photo', data: 'data:image/png;base64,mask', is_mask: true, mask_for: 'photo.png' }
      ];
      const card = createCard('user', badge, 'Masked', 'en', 'mid-mask', true, images);
      const cardHtml = card.find('.card-text').html();
      expect(cardHtml).toContain('mask-overlay-container');
      expect(cardHtml).toContain('mask-overlay');
    });

    it('includes TTS play/stop buttons on Chrome', () => {
      global.runningOnChrome = true;
      const card = createCard('user', badge, 'Hi');
      const html = card[0].outerHTML;
      expect(html).toContain('func-play');
      expect(html).toContain('func-stop');
    });

    it('omits TTS buttons on non-Chrome/Edge/Safari', () => {
      global.runningOnChrome = false;
      global.runningOnEdge = false;
      global.runningOnSafari = false;
      const card = createCard('user', badge, 'Hi');
      const html = card[0].outerHTML;
      expect(html).not.toContain('func-play');
      expect(html).not.toContain('func-stop');
    });

    it('handles null/undefined html gracefully', () => {
      expect(createCard('user', badge, null).length).toBe(1);
      expect(createCard('user', badge, undefined).length).toBe(1);
    });

    it('applies role-specific CSS classes', () => {
      expect(createCard('user', badge, 'X').find('.card-body').length).toBeGreaterThan(0);
      expect(createCard('assistant', badge, 'X')[0].outerHTML).toContain('role-assistant');
      expect(createCard('system', badge, 'X')[0].outerHTML).toContain('role-system');
      expect(createCard('info', badge, 'X')[0].outerHTML).toContain('role-info');
    });
  });

  // ── window exports ──────────────────────────────────────
  describe('exports', () => {
    it('exports escapeHtml to window', () => {
      expect(window.escapeHtml).toBe(escapeHtml);
    });

    it('exports createCard to window', () => {
      expect(window.createCard).toBe(createCard);
    });
  });
});
