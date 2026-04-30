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

    it('renders compact one-line rows with title, vis dot, turns, relative time', () => {
      const rows = [
        {
          conversation_id: 'A', title: 'Alpha Talk', source: 'ted-talk',
          language: 'en', visibility: 'shareable', turns_count: 12,
          messages_count: 12, created_at: new Date().toISOString()
        },
        {
          conversation_id: 'B', title: '', source: 'monadic-chat',
          language: 'ja', visibility: 'personal', turns_count: 4,
          messages_count: 4, created_at: new Date().toISOString()
        }
      ];
      lib.render(container, rows);
      const drawn = container.querySelectorAll('.library-row-compact');
      expect(drawn.length).toBe(2);
      expect(drawn[0].textContent).toContain('Alpha Talk');
      expect(drawn[0].textContent).toContain('12T');  // turn count
      expect(drawn[1].textContent).toContain('(untitled)');
      // The compact sidebar row no longer carries an inline delete button —
      // delete is now exposed through the Browse modal's action menu.
      expect(container.querySelector('.library-row-delete')).toBeNull();
    });

    it('escapes HTML in titles and conversation IDs', () => {
      lib.render(container, [{
        conversation_id: '<bad>', title: '<img src=x onerror=alert(1)>',
        visibility: 'personal', created_at: new Date().toISOString()
      }]);
      expect(container.innerHTML).not.toContain('<img');
      expect(container.innerHTML).toContain('&lt;img');
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

  describe('readModalSelections', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('returns title text and chosen visibility', () => {
      document.body.innerHTML = `
        <input id="library-save-title" value="My Conversation">
        <input type="radio" name="librarySaveVisibility" value="personal">
        <input type="radio" name="librarySaveVisibility" value="shareable" checked>
      `;
      expect(lib.readModalSelections()).toEqual({ title: 'My Conversation', visibility: 'shareable' });
    });

    it('defaults to personal when no radio is checked', () => {
      document.body.innerHTML = '<input id="library-save-title" value="">';
      expect(lib.readModalSelections()).toEqual({ title: '', visibility: 'personal' });
    });
  });

  describe('buildSavePayload', () => {
    let originalSetParams;

    beforeEach(() => {
      originalSetParams = global.window.setParams;
      global.window.setParams = () => ({ app_name: 'ChatOpenAI', model: 'gpt-5.4', initiate_from_assistant: true });
      global.window.messages = [
        { role: 'system', text: 'sys', mid: 1 },
        { role: 'user', text: 'Hi', mid: 2 },
        { role: 'assistant', text: 'Hello!', mid: 3, thinking: 'reasoning text' }
      ];
      document.body.innerHTML = '<input id="initial-prompt" value="You are a helper.">';
    });

    afterEach(() => {
      global.window.setParams = originalSetParams;
      delete global.window.messages;
      document.body.innerHTML = '';
    });

    it('builds payload with replaced system prompt and skips the leading session system message', () => {
      const payload = lib.buildSavePayload({ title: '  Demo  ', visibility: 'personal' });
      expect(payload.parameters.app_name).toBe('ChatOpenAI');
      expect(payload.parameters.initiate_from_assistant).toBeUndefined();
      expect(payload.visibility).toBe('personal');
      expect(payload.title).toBe('Demo');
      // First entry is the synthesized system message; the original
      // session system entry must be dropped to avoid duplication.
      expect(payload.messages.length).toBe(3);
      expect(payload.messages[0].role).toBe('system');
      expect(payload.messages[0].text).toBe('You are a helper.');
      expect(payload.messages[1]).toMatchObject({ role: 'user', text: 'Hi' });
      expect(payload.messages[2]).toMatchObject({ role: 'assistant', text: 'Hello!', thinking: 'reasoning text' });
    });

    it('includes monadic_state when supplied', () => {
      const payload = lib.buildSavePayload({ visibility: 'shareable', monadicState: { foo: 1 } });
      expect(payload.monadic_state).toEqual({ foo: 1 });
      expect(payload.visibility).toBe('shareable');
    });

    it('omits an empty title from the payload', () => {
      const payload = lib.buildSavePayload({ title: '   ', visibility: 'personal' });
      expect(payload.title).toBeUndefined();
    });
  });

  describe('handleConversations / handleStats / handleSavedMessage', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('renders compact inventory rows into #library-recent on library_conversations', () => {
      document.body.innerHTML = '<div id="library-recent"></div>'
        + '<span id="library-total-badge"></span>';
      lib.handleConversations({ content: [
        { conversation_id: 'A', title: 'Alpha', visibility: 'personal',
          turns_count: 3, created_at: new Date().toISOString() }
      ] });
      const html = document.getElementById('library-recent').innerHTML;
      expect(html).toMatch(/Alpha/);
      expect(html).toMatch(/data-conversation-id="A"/);
      // Total badge updates with the row count.
      expect(document.getElementById('library-total-badge').textContent).toBe('1');
    });

    it('limits the sidebar to the 5 most recent rows even when the server returns more', () => {
      document.body.innerHTML = '<div id="library-recent"></div>'
        + '<span id="library-total-badge"></span>';
      const rows = Array.from({ length: 12 }, (_, i) => ({
        conversation_id: 'C' + i, title: 'Conv ' + i, visibility: 'personal',
        turns_count: 1, created_at: new Date().toISOString()
      }));
      lib.handleConversations({ content: rows });
      const drawn = document.getElementById('library-recent').querySelectorAll('.library-row-compact');
      expect(drawn.length).toBe(5);
      // Badge still reflects the full total.
      expect(document.getElementById('library-total-badge').textContent).toBe('12');
    });

    it('writes the formatted stats line into #library-stats-info', () => {
      document.body.innerHTML = '<div id="library-stats-info"></div>';
      lib.handleStats({ content: { conversations_total: 4, conversations_personal: 3, conversations_shareable: 1 } });
      expect(document.getElementById('library-stats-info').textContent)
        .toBe('Knowledge Base: 4 total (3 personal, 1 shareable)');
    });

    it('refreshes list and stats after a successful save', () => {
      lib.handleSavedMessage({ res: 'success', conversation_id: 'X', visibility: 'personal' });
      expect(sentMessages.some(m => m.message === 'LIBRARY_LIST')).toBe(true);
      expect(sentMessages.some(m => m.message === 'LIBRARY_STATS')).toBe(true);
    });

    it('does not refresh the list when save fails', () => {
      const before = sentMessages.length;
      const origAlert = global.window.alert;
      global.window.alert = () => {};
      try {
        lib.handleSavedMessage({ res: 'failure', content: 'qdrant down' });
      } finally {
        global.window.alert = origAlert;
      }
      const newSends = sentMessages.slice(before);
      expect(newSends.find(m => m.message === 'LIBRARY_LIST')).toBeUndefined();
    });
  });

  describe('init', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('binds Save / Browse / Confirm buttons when present', () => {
      document.body.innerHTML = `
        <button id="library-save"></button>
        <button id="library-browse"></button>
        <button id="library-save-confirm"></button>
      `;
      lib.init();
      expect(typeof document.getElementById('library-save').onclick).toBe('function');
      expect(typeof document.getElementById('library-browse').onclick).toBe('function');
      expect(typeof document.getElementById('library-save-confirm').onclick).toBe('function');
    });

    it('opening the Browse modal auto-refreshes inventory + stats', () => {
      // The previous explicit Refresh button is gone — opening Browse
      // is the implicit refresh trigger. Regression guard: if someone
      // re-introduces the Refresh button, the auto-fetch on open should
      // remain so the user always sees a fresh snapshot.
      const before = sentMessages.length;
      lib.openBrowseModal();
      const after = sentMessages.slice(before);
      expect(after.find(m => m.message === 'LIBRARY_LIST')).toBeDefined();
      expect(after.find(m => m.message === 'LIBRARY_STATS')).toBeDefined();
    });
  });

  describe('relativeTime', () => {
    it('reports recent timestamps in seconds/minutes/hours', () => {
      const now = Date.now();
      expect(lib.relativeTime(new Date(now - 30 * 1000).toISOString())).toMatch(/s$/);
      expect(lib.relativeTime(new Date(now - 5 * 60 * 1000).toISOString())).toMatch(/m$/);
      expect(lib.relativeTime(new Date(now - 3 * 60 * 60 * 1000).toISOString())).toMatch(/h$/);
    });

    it('returns the empty string for nullish input', () => {
      expect(lib.relativeTime(null)).toBe('');
      expect(lib.relativeTime(undefined)).toBe('');
    });
  });

  describe('compactRowMarkup', () => {
    it('produces a one-line row with vis dot, truncated title, turns and time', () => {
      const html = lib.compactRowMarkup({
        conversation_id: 'X', title: 'Hello world', visibility: 'shareable',
        turns_count: 7, created_at: new Date().toISOString()
      });
      expect(html).toContain('library-row-compact');
      expect(html).toContain('library-vis-dot');
      expect(html).toContain('Hello world');
      expect(html).toContain('7T');
      // No inline delete button in compact row — actions live in browse modal.
      expect(html).not.toContain('library-row-delete');
    });

    it('truncates very long titles', () => {
      const longTitle = 'a'.repeat(100);
      const html = lib.compactRowMarkup({
        conversation_id: 'X', title: longTitle, visibility: 'personal',
        turns_count: 1, created_at: new Date().toISOString()
      });
      expect(html).toContain('…');
    });
  });

  describe('browseRowMarkup', () => {
    it('uses 3 inline icon buttons instead of a dropdown menu', () => {
      const html = lib.browseRowMarkup({
        conversation_id: 'X', title: 'T', visibility: 'personal',
        turns_count: 3, source: 'monadic-chat', language: 'en',
        created_at: new Date().toISOString()
      }, 0);
      // Inline buttons: detail / toggle / delete must all be plain
      // <button> elements wired by class — no dropdown wrapper or
      // dropdown-menu list exists in the wide modal.
      expect(html).not.toContain('dropdown-menu');
      expect(html).not.toContain('data-bs-toggle="dropdown"');
      expect(html).toMatch(/<button[^>]+class="[^"]*library-action-detail/);
      expect(html).toMatch(/<button[^>]+class="[^"]*library-action-toggle/);
      expect(html).toMatch(/<button[^>]+class="[^"]*library-action-delete/);
    });

    it('renders a type-icon cell as the leftmost column for forward-compat with PDF/code/etc.', () => {
      var html = lib.browseRowMarkup({
        conversation_id: 'X', title: 'T', visibility: 'personal',
        turns_count: 1, content_type: 'conversation',
        created_at: new Date().toISOString()
      }, 0);
      // Type icon is the first <td>; uses the conversation icon.
      expect(html).toMatch(/<tr[^>]*>\s*<td[^>]*>[^<]*<i[^>]*fa-comments/);
      expect(html).toContain('aria-label="conversation"');
    });

    it('typeIconHtml falls back to a generic file icon for unknown types', () => {
      var html = lib.typeIconHtml('weird');
      expect(html).toContain('fa-file');
      expect(html).toContain('weird');
    });

    it('typeIconHtml maps known types to specific icons', () => {
      expect(lib.typeIconHtml('pdf')).toContain('fa-file-pdf');
      expect(lib.typeIconHtml('code')).toContain('fa-file-code');
      expect(lib.typeIconHtml('markdown')).toContain('fa-file-lines');
      expect(lib.typeIconHtml('audio')).toContain('fa-file-audio');
    });

    it('flips the toggle target visibility based on the current value', () => {
      var personalRow = lib.browseRowMarkup({
        conversation_id: 'A', title: 'A', visibility: 'personal', turns_count: 1,
        created_at: new Date().toISOString()
      }, 0);
      expect(personalRow).toContain('data-next-vis="shareable"');

      var shareableRow = lib.browseRowMarkup({
        conversation_id: 'B', title: 'B', visibility: 'shareable', turns_count: 1,
        created_at: new Date().toISOString()
      }, 1);
      expect(shareableRow).toContain('data-next-vis="personal"');
    });
  });

  describe('applyFilters / browse pagination', () => {
    function seedRows(n) {
      return Array.from({ length: n }, (_, i) => ({
        conversation_id: 'r-' + i,
        title: 'Talk ' + i,
        source: i % 2 === 0 ? 'monadic-chat' : 'ted-talk',
        language: i % 3 === 0 ? 'ja' : 'en',
        visibility: i % 4 === 0 ? 'shareable' : 'personal',
        turns_count: i,
        created_at: new Date(Date.now() - i * 60 * 1000).toISOString()
      }));
    }

    it('applyFilters narrows by visibility and search term', () => {
      lib._state.allRows = seedRows(20);
      lib._state.visibilityFilter = 'shareable';
      lib._state.searchTerm = '';
      lib.applyFilters();
      expect(lib._state.filteredRows.every(r => r.visibility === 'shareable')).toBe(true);

      lib._state.visibilityFilter = 'all';
      lib._state.searchTerm = 'talk 1'; // matches Talk 1, 10..19
      lib.applyFilters();
      expect(lib._state.filteredRows.length).toBe(11);
    });

    it('applyFilters sorts by created_desc by default', () => {
      lib._state.allRows = seedRows(5);
      lib._state.searchTerm = '';
      lib._state.visibilityFilter = 'all';
      lib._state.sortKey = 'created_desc';
      lib.applyFilters();
      const titles = lib._state.filteredRows.map(r => r.title);
      // Newest first → Talk 0 (Date.now()) is newest, Talk 4 oldest.
      expect(titles[0]).toBe('Talk 0');
      expect(titles[4]).toBe('Talk 4');
    });

    it('applyFilters can sort by title A→Z and turns desc', () => {
      lib._state.allRows = [
        { conversation_id: 'a', title: 'Banana', turns_count: 3, created_at: '2026-01-01' },
        { conversation_id: 'b', title: 'Apple',  turns_count: 9, created_at: '2026-01-02' },
        { conversation_id: 'c', title: 'Cherry', turns_count: 1, created_at: '2026-01-03' }
      ];
      lib._state.visibilityFilter = 'all';
      lib._state.searchTerm = '';

      lib._state.sortKey = 'title_asc';
      lib.applyFilters();
      expect(lib._state.filteredRows.map(r => r.title)).toEqual(['Apple', 'Banana', 'Cherry']);

      lib._state.sortKey = 'turns_desc';
      lib.applyFilters();
      expect(lib._state.filteredRows.map(r => r.turns_count)).toEqual([9, 3, 1]);
    });

    it('applyFilters caps page index when filter removes pages', () => {
      lib._state.allRows = seedRows(60);
      lib._state.pageSize = 20;
      lib._state.page = 2;  // last page (40-59)
      lib._state.visibilityFilter = 'shareable';  // now ~15 rows → 1 page
      lib._state.searchTerm = '';
      lib.applyFilters();
      expect(lib._state.page).toBe(0);
    });
  });

  describe('handleVisibilityUpdated', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('updates the cached row visibility on success and triggers stats refresh', () => {
      document.body.innerHTML = '<div id="library-recent"></div>'
        + '<span id="library-total-badge"></span>';
      lib.handleConversations({ content: [
        { conversation_id: 'X', title: 'T', visibility: 'personal',
          turns_count: 1, created_at: new Date().toISOString() }
      ] });
      const before = sentMessages.length;
      lib.handleVisibilityUpdated({ res: 'success', conversation_id: 'X', visibility: 'shareable' });
      expect(lib._state.allRows.find(r => r.conversation_id === 'X').visibility).toBe('shareable');
      // Stats refresh must be requested so the personal/shareable counts update.
      expect(sentMessages.slice(before).some(m => m.message === 'LIBRARY_STATS')).toBe(true);
    });

    it('does not mutate cache on failure', () => {
      lib._state.allRows = [{ conversation_id: 'X', visibility: 'personal' }];
      lib.handleVisibilityUpdated({ res: 'failure', conversation_id: 'X', content: 'qdrant down' });
      expect(lib._state.allRows[0].visibility).toBe('personal');
    });
  });

  describe('setVisibility / browse action menu', () => {
    it('setVisibility sends LIBRARY_TOGGLE_VISIBILITY with conversation_id+visibility', () => {
      lib.setVisibility('conv-9', 'shareable');
      const msg = sentMessages.find(m => m.message === 'LIBRARY_TOGGLE_VISIBILITY');
      expect(msg).toBeDefined();
      expect(msg.contents).toEqual({ conversation_id: 'conv-9', visibility: 'shareable' });
    });
  });

  describe('Viewer modal', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    function seedViewerDom() {
      document.body.innerHTML =
        '<div id="libraryViewerModal">' +
        '  <span id="library-viewer-title"></span>' +
        '  <div id="library-viewer-meta"></div>' +
        '  <div id="library-viewer-loading" style="display:none;"></div>' +
        '  <div id="library-viewer-empty" style="display:none;"></div>' +
        '  <div id="library-viewer-messages"></div>' +
        '  <button id="library-viewer-toggle-vis" data-next-vis="shareable"></button>' +
        '  <span id="library-viewer-toggle-label"></span>' +
        '  <button id="library-viewer-delete"></button>' +
        '</div>';
    }

    it('renderViewerMessages emits a block per message with role headers and data-role attribute', () => {
      seedViewerDom();
      const container = document.getElementById('library-viewer-messages');
      lib.renderViewerMessages([
        { id: 'm1', speaker: { id: 'human' }, text: 'Hi there' },
        { id: 'm2', speaker: { id: 'assistant' }, text: 'Hello!' }
      ], container);
      const blocks = container.querySelectorAll('.library-viewer-message');
      expect(blocks.length).toBe(2);
      expect(blocks[0].getAttribute('data-role')).toBe('human');
      expect(blocks[0].textContent).toContain('human');
      expect(blocks[0].textContent).toContain('Hi there');
      expect(blocks[1].getAttribute('data-role')).toBe('assistant');
      expect(blocks[1].textContent).toContain('assistant');
      expect(blocks[1].textContent).toContain('Hello!');
    });

    it('wraps system prompts in a collapsed-by-default <details> element', () => {
      seedViewerDom();
      const container = document.getElementById('library-viewer-messages');
      lib.renderViewerMessages([
        { id: 's1', speaker: { id: 'system' }, text: 'You are a long system prompt with many rules and policies...' },
        { id: 'm1', speaker: { id: 'human' }, text: 'Hi' }
      ], container);
      const sysBlock = container.querySelector('.library-viewer-message[data-role="system"]');
      const details = sysBlock && sysBlock.querySelector('details.library-viewer-system');
      expect(details).not.toBeNull();
      // Default closed: no `open` attribute on the details element.
      expect(details.hasAttribute('open')).toBe(false);
      // Summary contains the localized "System prompt" label.
      expect(details.querySelector('summary').textContent).toContain('System prompt');
      // Non-system messages are NOT wrapped in details.
      const humanBlock = container.querySelector('.library-viewer-message[data-role="human"]');
      expect(humanBlock.querySelector('details')).toBeNull();
    });

    it('handleConversationData success path renders messages', () => {
      seedViewerDom();
      lib._state.allRows = [{ conversation_id: 'X', visibility: 'personal', title: 'T',
        turns_count: 1, messages_count: 1, created_at: new Date().toISOString() }];
      lib._state.selectedId = 'X';
      lib.handleConversationData({
        res: 'success', conversation_id: 'X',
        conversation: { messages: [{ id: 'm', speaker: { id: 'human' }, text: 'Hello' }] }
      });
      expect(document.querySelectorAll('.library-viewer-message').length).toBe(1);
      expect(document.getElementById('library-viewer-empty').style.display).toBe('none');
    });

    it('handleConversationData failure path shows the empty alert with the error message', () => {
      seedViewerDom();
      lib.handleConversationData({ res: 'failure', content: 'boom' });
      const empty = document.getElementById('library-viewer-empty');
      expect(empty.style.display).toBe('');
      expect(empty.textContent).toContain('boom');
    });

    it('handleConversationData success but no messages shows empty state', () => {
      seedViewerDom();
      lib.handleConversationData({
        res: 'success', conversation_id: 'X',
        conversation: { messages: [] }
      });
      const empty = document.getElementById('library-viewer-empty');
      expect(empty.style.display).toBe('');
    });

    it('openViewerModal sends LIBRARY_GET_CONVERSATION', () => {
      seedViewerDom();
      lib._state.allRows = [{ conversation_id: 'Y', visibility: 'personal',
        turns_count: 1, created_at: new Date().toISOString() }];
      const before = sentMessages.length;
      lib.openViewerModal('Y');
      const msg = sentMessages.slice(before).find(m => m.message === 'LIBRARY_GET_CONVERSATION');
      expect(msg).toBeDefined();
      expect(msg.contents).toEqual({ conversation_id: 'Y' });
    });
  });

  describe('mc:conv link click intercept', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('init wires document-level click handler that opens viewer for mc:conv links', () => {
      document.body.innerHTML =
        '<a href="mc:conv:abc-123" id="cite">Talk</a>' +
        '<div id="libraryViewerModal">' +
        '  <span id="library-viewer-title"></span>' +
        '  <div id="library-viewer-meta"></div>' +
        '  <div id="library-viewer-loading" style="display:none;"></div>' +
        '  <div id="library-viewer-empty" style="display:none;"></div>' +
        '  <div id="library-viewer-messages"></div>' +
        '</div>';
      lib.init();
      const before = sentMessages.length;
      const link = document.getElementById('cite');
      link.click();
      const msg = sentMessages.slice(before).find(m => m.message === 'LIBRARY_GET_CONVERSATION');
      expect(msg).toBeDefined();
      expect(msg.contents).toEqual({ conversation_id: 'abc-123' });
    });

    it('regular http links are not intercepted', () => {
      document.body.innerHTML = '<a href="https://example.com" id="extlink">x</a>';
      lib.init();
      const before = sentMessages.length;
      // jsdom prevents real navigation, but we just need to ensure no
      // LIBRARY_GET_CONVERSATION fires for non-mc links.
      document.getElementById('extlink').click();
      const after = sentMessages.slice(before)
        .filter(m => m.message === 'LIBRARY_GET_CONVERSATION');
      expect(after.length).toBe(0);
    });
  });

  describe('RAG toggle', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('setRagToggle(true) sends LIBRARY_RAG_TOGGLE with enabled=true', () => {
      const ok = lib.setRagToggle(true);
      expect(ok).toBe(true);
      const msg = sentMessages.find(m => m.message === 'LIBRARY_RAG_TOGGLE');
      expect(msg).toBeDefined();
      expect(msg.contents).toEqual({ enabled: true });
    });

    it('setRagToggle(false) sends LIBRARY_RAG_TOGGLE with enabled=false', () => {
      lib.setRagToggle(false);
      const msg = sentMessages.find(m => m.message === 'LIBRARY_RAG_TOGGLE');
      expect(msg.contents).toEqual({ enabled: false });
    });

    it('requestRagState sends LIBRARY_RAG_QUERY', () => {
      lib.requestRagState();
      expect(sentMessages.some(m => m.message === 'LIBRARY_RAG_QUERY')).toBe(true);
    });

    it('handleRagState syncs the checkbox without re-firing change', () => {
      document.body.innerHTML = '<input type="checkbox" id="library-rag-toggle">';
      const el = document.getElementById('library-rag-toggle');
      let changes = 0;
      el.onchange = () => { changes += 1; };
      lib.handleRagState({ enabled: true });
      expect(el.checked).toBe(true);
      expect(changes).toBe(0);
      lib.handleRagState({ enabled: false });
      expect(el.checked).toBe(false);
      expect(changes).toBe(0);
    });

    it('init binds the toggle change to setRagToggle', () => {
      document.body.innerHTML = '<input type="checkbox" id="library-rag-toggle">';
      lib.init();
      const el = document.getElementById('library-rag-toggle');
      el.checked = true;
      el.onchange();
      const msg = sentMessages.find(m => m.message === 'LIBRARY_RAG_TOGGLE');
      expect(msg).toBeDefined();
      expect(msg.contents).toEqual({ enabled: true });
    });
  });
});
