/**
 * @jest-environment jsdom
 */

describe('library-panel module', () => {
  let lib;
  let sentMessages;

  beforeEach(() => {
    jest.resetModules();
    sentMessages = [];
    // Stub WebSocket so send() does not throw.
    global.window.ws = {
      send: (payload) => sentMessages.push(JSON.parse(payload))
    };
    require('../../docker/services/ruby/public/js/monadic/library-panel.js');
    lib = global.window.libraryPanel;
  });

  afterEach(() => {
    delete global.window.ws;
    delete global.window.libraryPanel;
  });

  describe('escapeHtml', () => {
    it('escapes &, <, >, ", \' so HTML cannot be injected', () => {
      const out = lib.escapeHtml('<script>alert("x")</script>&\'');
      expect(out).toBe('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;&amp;&#39;');
    });

    it('coerces null / undefined into the empty string', () => {
      expect(lib.escapeHtml(null)).toBe('');
      expect(lib.escapeHtml(undefined)).toBe('');
    });
  });

  describe('visibilityBadge', () => {
    it('renders shareable as the green success badge', () => {
      expect(lib.visibilityBadge('shareable')).toContain('bg-success');
    });
    it('renders personal as the secondary badge', () => {
      expect(lib.visibilityBadge('personal')).toContain('bg-secondary');
    });
    it('handles unknown / missing visibility safely', () => {
      expect(lib.visibilityBadge(undefined)).toContain('unknown');
    });
  });

  describe('send', () => {
    it('writes a JSON message to window.ws when present', () => {
      const ok = lib.send('LIBRARY_LIST');
      expect(ok).toBe(true);
      expect(sentMessages).toEqual([{ message: 'LIBRARY_LIST' }]);
    });

    it('attaches payload fields to the message body', () => {
      lib.send('LIBRARY_DELETE', { contents: 'conv-x' });
      expect(sentMessages[0]).toEqual({ message: 'LIBRARY_DELETE', contents: 'conv-x' });
    });

    it('returns false when window.ws is missing', () => {
      delete global.window.ws;
      expect(lib.send('LIBRARY_LIST')).toBe(false);
    });
  });

  describe('render', () => {
    let container;

    beforeEach(() => {
      document.body.innerHTML = '<div id="library-panel"></div>';
      container = document.getElementById('library-panel');
    });

    it('shows an empty-state message when rows is []', () => {
      lib.render(container, []);
      expect(container.textContent).toContain('Knowledge Base is empty');
    });

    it('renders one row per conversation with the title and meta', () => {
      const rows = [
        {
          conversation_id: 'A', title: 'Alpha Talk', source: 'ted-talk',
          language: 'en', visibility: 'shareable', turns_count: 12, messages_count: 12
        },
        {
          conversation_id: 'B', title: '', source: 'monadic-chat',
          language: 'ja', visibility: 'personal', turns_count: 4, messages_count: 4
        }
      ];
      lib.render(container, rows);
      const drawn = container.querySelectorAll('.library-row');
      expect(drawn.length).toBe(2);

      // Title and metadata for the first row
      expect(drawn[0].textContent).toContain('Alpha Talk');
      expect(drawn[0].textContent).toContain('ted-talk');
      expect(drawn[0].textContent).toContain('shareable');

      // Untitled row falls back to "(untitled)"
      expect(drawn[1].textContent).toContain('(untitled)');
      expect(drawn[1].textContent).toContain('personal');
    });

    it('escapes HTML in titles and conversation IDs', () => {
      lib.render(container, [{
        conversation_id: '<bad>', title: '<img src=x onerror=alert(1)>',
        visibility: 'personal'
      }]);
      expect(container.innerHTML).not.toContain('<img');
      expect(container.innerHTML).toContain('&lt;img');
    });

    it('wires up the per-row delete button to send LIBRARY_DELETE', () => {
      window.confirm = jest.fn().mockReturnValue(true);
      lib.render(container, [
        { conversation_id: 'conv-1', title: 'X', visibility: 'personal' }
      ]);
      const btn = container.querySelector('.library-row-delete');
      btn.click();
      expect(window.confirm).toHaveBeenCalled();
      expect(sentMessages.find(m => m.message === 'LIBRARY_DELETE'))
        .toEqual({ message: 'LIBRARY_DELETE', contents: 'conv-1' });
    });

    it('does not send delete when the confirm dialog is cancelled', () => {
      window.confirm = jest.fn().mockReturnValue(false);
      lib.render(container, [
        { conversation_id: 'conv-1', title: 'X', visibility: 'personal' }
      ]);
      container.querySelector('.library-row-delete').click();
      expect(sentMessages.find(m => m.message === 'LIBRARY_DELETE')).toBeUndefined();
    });
  });

  describe('handleDeleted', () => {
    let container;

    beforeEach(() => {
      document.body.innerHTML = '<div id="library-panel"></div>';
      container = document.getElementById('library-panel');
      lib.render(container, [
        { conversation_id: 'conv-1', title: 'first', visibility: 'personal' },
        { conversation_id: 'conv-2', title: 'second', visibility: 'shareable' }
      ]);
    });

    it('removes the row optimistically when res is success', () => {
      lib.handleDeleted({ res: 'success', conversation_id: 'conv-1' }, container);
      const remaining = container.querySelectorAll('[data-conversation-id]');
      expect(remaining.length).toBe(1);
      expect(remaining[0].getAttribute('data-conversation-id')).toBe('conv-2');
    });

    it('always re-fetches LIBRARY_LIST after a delete attempt', () => {
      lib.handleDeleted({ res: 'failure' }, container);
      expect(sentMessages.find(m => m.message === 'LIBRARY_LIST')).toBeDefined();
    });
  });

  describe('formatStats', () => {
    it('renders a single-line summary', () => {
      const out = lib.formatStats({
        conversations_total: 10, conversations_personal: 7, conversations_shareable: 3
      });
      expect(out).toBe('Knowledge Base: 10 total (7 personal, 3 shareable)');
    });

    it('returns the empty string for nullish input', () => {
      expect(lib.formatStats(null)).toBe('');
    });
  });
});
