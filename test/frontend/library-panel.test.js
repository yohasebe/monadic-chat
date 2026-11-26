/**
 * @jest-environment jsdom
 */

describe('library-panel module', () => {
  let lib;
  let sentMessages;

  let safeWsSendCalls;

  beforeEach(() => {
    jest.resetModules();
    sentMessages = [];
    safeWsSendCalls = [];
    // The library panel routes every LIBRARY_* message through
    // window.safeWsSend (the H7 wrapper). Capture both the body and
    // the opts each call site uses so tests can assert on either.
    global.window.safeWsSend = (body, opts) => {
      sentMessages.push(body);
      safeWsSendCalls.push({ body: body, opts: opts || {} });
      return { sent: true, state: 'OPEN' };
    };
    require('../../docker/services/ruby/public/js/monadic/library-panel.js');
    lib = global.window.libraryPanel;
  });

  afterEach(() => {
    delete global.window.safeWsSend;
    delete global.window.libraryPanel;
  });

  describe('escapeHtml', () => {
    it('escapes &, <, >, ", \' so HTML cannot be injected', () => {
      const out = lib.escapeHtml('<script>alert("x")</script>&\'');
      // Canonical implementation (text-utils.js) emits &#039; for single
      // quotes; the former local copy emitted &#39;. Same rendered output.
      expect(out).toBe('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;&amp;&#039;');
    });

    it('coerces null / undefined into the empty string', () => {
      expect(lib.escapeHtml(null)).toBe('');
      expect(lib.escapeHtml(undefined)).toBe('');
    });
  });

  describe('send', () => {
    it('routes LIBRARY_LIST through window.safeWsSend and reports success', () => {
      const ok = lib.send('LIBRARY_LIST');
      expect(ok).toBe(true);
      expect(sentMessages).toEqual([{ message: 'LIBRARY_LIST' }]);
    });

    it('attaches payload fields to the message body', () => {
      lib.send('LIBRARY_DELETE', { contents: 'conv-x' });
      expect(sentMessages[0]).toEqual({ message: 'LIBRARY_DELETE', contents: 'conv-x' });
    });

    it('returns false when window.safeWsSend is missing', () => {
      delete global.window.safeWsSend;
      expect(lib.send('LIBRARY_LIST')).toBe(false);
    });

    it('returns false when safeWsSend reports the message neither sent nor queued', () => {
      global.window.safeWsSend = () => ({ sent: false, queued: false, state: 'CLOSED' });
      expect(lib.send('LIBRARY_LIST')).toBe(false);
    });

    it('returns true when safeWsSend reports the message was queued for replay', () => {
      global.window.safeWsSend = () => ({ sent: false, queued: true, state: 'CONNECTING' });
      expect(lib.send('LIBRARY_LIST')).toBe(true);
    });

    it('forwards opts (e.g. silentDrop) so non-idempotent background sends do not alert', () => {
      lib.send('LIBRARY_SUGGEST_TITLE', { contents: { messages: [] } }, { silentDrop: true });
      expect(safeWsSendCalls[0].opts).toEqual({ silentDrop: true });
    });
  });

  describe('handleConversations / handleDeletedMessage', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('counts every entry the server gives, past any page', () => {
      document.body.innerHTML = '<table><tbody id="library-browse-tbody"></tbody></table><span id="library-browse-count"></span>';
      const rows = Array.from({ length: 501 }, (_, i) => ({ conversation_id: 'C' + i, title: 'Conv ' + i,
        created_at: new Date(2026, 0, 1, 0, 0, i).toISOString() }));
      lib.handleConversations({ content: rows, total: 501 });
      expect(document.getElementById('library-browse-count').textContent).toBe('501 / 501');
    });

    it('takes a deleted entry out and fetches the list again', () => {
      lib._state.allRows = [{ conversation_id: 'A', title: 'A' }, { conversation_id: 'B', title: 'B' }];
      const before = sentMessages.length;
      lib.handleDeletedMessage({ res: 'success', conversation_id: 'A' });
      expect(lib._state.allRows.map(r => r.conversation_id)).toEqual(['B']);
      expect(sentMessages.slice(before).map(m => m.message)).toEqual(['LIBRARY_LIST']);
    });
  });

  describe('init', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('opening the Library fetches the list and shows the Library tab of the side column', () => {
      const layout = { hidden: true, pane: 'work' };
      window.LayoutController = {
        isMenuHidden: () => layout.hidden,
        setMenuHidden: (h) => { layout.hidden = h; },
        setPane: (p) => { layout.pane = p; }
      };
      try {
        const before = sentMessages.length;
        lib.openBrowseModal();
        expect(sentMessages.slice(before).map(m => m.message)).toEqual(['LIBRARY_LIST']);
        expect(layout).toEqual({ hidden: false, pane: 'library' });
      } finally {
        delete window.LayoutController;
      }
    });
  });

  describe('keeping the conversation', () => {
    it('asks the server to put the chat on the work screen', () => {
      const before = sentMessages.length;
      lib.draftConversation();
      expect(sentMessages.slice(before).map(m => m.message)).toEqual(['LIBRARY_CONVERSATION_DRAFT']);
    });

    it('shows the work screen once the record is there', () => {
      const layout = {};
      window.LayoutController = { setPane: (p) => { layout.pane = p; } };
      try {
        lib.handleConversationDraft({ item_id: 'i_1' });
        expect(layout.pane).toBe('work');
      } finally {
        delete window.LayoutController;
      }
    });

    it('says why nothing was put, the work screen left as it is', () => {
      const layout = {};
      window.LayoutController = { setPane: (p) => { layout.pane = p; } };
      const alerts = [];
      window.setAlert = (html) => alerts.push(html);
      try {
        lib.handleConversationDraft({ error: 'not_saved_by_app' });
        lib.handleConversationDraft({ error: 'hides_words' });
        expect(layout.pane).toBeUndefined();
        expect(alerts[0]).toMatch(/does not keep its conversations/);
        expect(alerts[1]).toMatch(/hides words/);
      } finally {
        delete window.LayoutController;
        delete window.setAlert;
      }
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

  describe('browseRowMarkup', () => {
    it('offers the chat a record was made from, only while that chat can be continued', () => {
      const resumed = [];
      window.HistoryPanel = { resume: (id) => resumed.push(id) };
      document.body.innerHTML = '<table><tbody id="library-browse-tbody"></tbody></table>';
      try {
        lib.handleConversations({ content: [
          { conversation_id: 'r1', title: 'Kept', source_chat_id: 'c_1', source_chat_resumable: true, created_at: new Date().toISOString() },
          { conversation_id: 'r2', title: 'Doc', created_at: new Date().toISOString() }
        ] });
        const buttons = document.querySelectorAll('#library-browse-tbody .library-action-chat');
        expect(buttons.length).toBe(1);
        buttons[0].click();
        expect(resumed).toEqual(['c_1']);
      } finally {
        delete window.HistoryPanel;
        document.body.innerHTML = '';
      }
    });

    it('opens the entry on the work screen from its row', () => {
      const opened = [];
      window.Workbench = { openLibrary: (id) => opened.push(id) };
      document.body.innerHTML = '<table><tbody id="library-browse-tbody"></tbody></table>';
      try {
        lib.handleConversations({ content: [{ conversation_id: 'conv-9', title: 'T', turns_count: 1,
          created_at: new Date().toISOString() }] });
        document.querySelector('#library-browse-tbody .library-action-open').click();
        expect(opened).toEqual(['conv-9']);
      } finally {
        delete window.Workbench;
        document.body.innerHTML = '';
      }
    });

    it('uses 2 inline icon buttons instead of a dropdown menu', () => {
      const html = lib.browseRowMarkup({
        conversation_id: 'X', title: 'T', scope_app: 'ChatOpenAI',
        turns_count: 3, source: 'monadic-chat', language: 'en',
        created_at: new Date().toISOString()
      }, 0);
      // Inline buttons: detail / delete must both be plain
      // <button> elements wired by class — no dropdown wrapper or
      // dropdown-menu list exists in the wide modal.
      expect(html).not.toContain('dropdown-menu');
      expect(html).not.toContain('data-bs-toggle="dropdown"');
      expect(html).toMatch(/<button[^>]+class="[^"]*library-action-detail/);
      expect(html).not.toContain('library-action-toggle');
      expect(html).toMatch(/<button[^>]+class="[^"]*library-action-delete/);
    });

    it('renders a type-icon cell as the leftmost column for forward-compat with PDF/code/etc.', () => {
      var html = lib.browseRowMarkup({
        conversation_id: 'X', title: 'T', scope_app: 'ChatOpenAI',
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

  });

  describe('applyFilters / browse pagination', () => {
    function seedRows(n) {
      return Array.from({ length: n }, (_, i) => ({
        conversation_id: 'r-' + i,
        title: 'Talk ' + i,
        source: i % 2 === 0 ? 'monadic-chat' : 'ted-talk',
        language: i % 3 === 0 ? 'ja' : 'en',
        scope_app: i % 4 === 0 ? 'Global' : 'ChatOpenAI',
        turns_count: i,
        created_at: new Date(Date.now() - i * 60 * 1000).toISOString()
      }));
    }

    it('applyFilters narrows by search term', () => {
      lib._state.allRows = seedRows(20);
      lib._state.searchTerm = 'talk 1'; // matches Talk 1, 10..19
      lib.applyFilters();
      expect(lib._state.filteredRows.length).toBe(11);
    });

    it('applyFilters sorts by created_desc by default', () => {
      lib._state.allRows = seedRows(5);
      lib._state.searchTerm = '';
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
      lib._state.searchTerm = 'talk 5';  // Talk 5, 50..59 → 1 page
      lib.applyFilters();
      expect(lib._state.page).toBe(0);
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
        '  <button id="library-viewer-toggle-scope" data-next-scope="Global"></button>' +
        '  <span id="library-viewer-toggle-label"></span>' +
        '  <button id="library-viewer-delete"></button>' +
        '</div>';
    }

    it('shows a passage as it was read for a reply, without the actions of an entry, or says it is gone', () => {
      seedViewerDom();
      document.getElementById('libraryViewerModal').insertAdjacentHTML('beforeend', '<button id="library-viewer-rename"></button>');
      lib.showExcerpt({ title: 'Tides', text: 'The moon pulls the sea.' });
      expect(document.getElementById('library-viewer-title').textContent).toBe('Tides');
      expect(document.getElementById('library-viewer-messages').textContent).toContain('The moon pulls the sea.');
      expect(document.getElementById('library-viewer-delete').style.display).toBe('none');
      expect(document.getElementById('library-viewer-rename').style.display).toBe('none');

      lib.showExcerpt({ title: 'Tides' });
      expect(document.getElementById('library-viewer-messages').textContent).toBe('This passage is no longer available.');
    });

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
      lib._state.allRows = [{ conversation_id: 'X', scope_app: 'ChatOpenAI', title: 'T',
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
      lib._state.allRows = [{ conversation_id: 'Y', scope_app: 'ChatOpenAI',
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

  describe('uploadLibraryFile (Import file)', () => {
    let originalFetch;
    beforeEach(() => {
      originalFetch = global.fetch;
      document.body.innerHTML = `
        <button id="library-browse-import">Import file</button>
        <input id="library-import-input" type="file">
      `;
    });
    afterEach(() => {
      global.fetch = originalFetch;
      document.body.innerHTML = '';
    });

    it('POSTs FormData to /library/import (202), polls status, and refreshes on success', async () => {
      let captured = null;
      // The async contract is: POST returns 202 + { import_id }, then
      // GET /library/import/status/:id is polled until stage='done'.
      global.fetch = jest.fn((url, opts) => {
        if (typeof url === 'string' && url.startsWith('/library/import/status/')) {
          return Promise.resolve({
            ok: true, status: 200,
            json: () => Promise.resolve({
              success: true, import_id: 'imp-1', stage: 'done',
              filename: 'paper.pdf', conversation_id: 'c1',
              scope_app: 'ChatOpenAI', counts: { summary: 1, turns: 5, trajectory: 1 }
            })
          });
        }
        captured = { url: url, opts: opts };
        return Promise.resolve({
          ok: true, status: 202,
          json: () => Promise.resolve({
            success: true, import_id: 'imp-1',
            status_url: '/library/import/status/imp-1',
            filename: 'paper.pdf', scope_app: 'Global'
          })
        });
      });
      const file = new File(['stub'], 'paper.pdf', { type: 'application/pdf' });
      const out = await lib.uploadLibraryFile(file, { title: 'Paper' });
      expect(captured.url).toBe('/library/import');
      expect(captured.opts.method).toBe('POST');
      expect(captured.opts.body instanceof FormData).toBe(true);
      expect(captured.opts.body.get('libraryFile')).toBe(file);
      expect(captured.opts.body.get('libraryTitle')).toBe('Paper');
      expect(captured.opts.body.get('libraryScopeApp')).toBeNull();
      // The final resolved value is the terminal status payload.
      expect(out.stage).toBe('done');
      expect(out.conversation_id).toBe('c1');
      // After success the panel re-pulls the list + stats:
      expect(sentMessages.find(m => m.message === 'LIBRARY_LIST')).toBeDefined();
    });

    it('rejects with the worker error message when the status endpoint reports stage="error"', async () => {
      global.fetch = jest.fn((url) => {
        if (typeof url === 'string' && url.startsWith('/library/import/status/')) {
          return Promise.resolve({
            ok: true, status: 200,
            json: () => Promise.resolve({
              success: true, import_id: 'imp-2', stage: 'error',
              error: 'Unsupported file extension: .xyz',
              filename: 'mystery.xyz'
            })
          });
        }
        return Promise.resolve({
          ok: true, status: 202,
          json: () => Promise.resolve({
            success: true, import_id: 'imp-2',
            status_url: '/library/import/status/imp-2',
            filename: 'mystery.xyz', scope_app: 'Global'
          })
        });
      });
      const file = new File(['stub'], 'mystery.xyz', { type: 'application/octet-stream' });
      await expect(lib.uploadLibraryFile(file)).rejects.toThrow(/Unsupported/);
      // No refresh on failure:
      expect(sentMessages.find(m => m.message === 'LIBRARY_LIST')).toBeUndefined();
    });

    it('rejects when POST returns a non-202 envelope (synchronous validation error)', async () => {
      global.fetch = jest.fn(() => Promise.resolve({
        ok: true, status: 200,
        json: () => Promise.resolve({ success: false, error: 'Could not determine upload size; rejected for safety.' })
      }));
      const file = new File(['stub'], 'bad.md', { type: 'text/markdown' });
      await expect(lib.uploadLibraryFile(file)).rejects.toThrow(/upload size/);
    });

    it('triggerImportPicker clicks the hidden file input', () => {
      const input = document.getElementById('library-import-input');
      let clicked = 0;
      input.click = () => { clicked += 1; };
      lib.triggerImportPicker();
      expect(clicked).toBe(1);
    });
  });

  describe('typeIconHtml sub-format detection', () => {
    it('falls back to the generic Word icon for content_type=document with no topics', () => {
      expect(lib.typeIconHtml('document', null)).toContain('fa-file-word');
    });
    it('uses the Excel icon when topics include "xlsx"', () => {
      expect(lib.typeIconHtml('document', ['xlsx'])).toContain('fa-file-excel');
    });
    it('uses the PowerPoint icon when topics include "pptx"', () => {
      expect(lib.typeIconHtml('document', ['pptx'])).toContain('fa-file-powerpoint');
    });
    it('falls back gracefully when topics is not an array', () => {
      expect(lib.typeIconHtml('document', 'docx')).toContain('fa-file-word');
    });
  });

  describe('rename conversation', () => {
    beforeEach(() => {
      document.body.innerHTML = `
        <span id="library-viewer-title">Old Title</span>
        <button id="library-viewer-rename"></button>
        <span id="library-viewer-rename-form" class="d-none">
          <input id="library-viewer-rename-input" type="text" value="Old Title">
          <button id="library-viewer-rename-save"></button>
          <button id="library-viewer-rename-cancel"></button>
        </span>
      `;
      lib._state.allRows = [{ conversation_id: 'c1', title: 'Old Title' }];
      lib._state.selectedId = 'c1';
    });

    it('submitRename sends LIBRARY_RENAME with the trimmed input', () => {
      const input = document.getElementById('library-viewer-rename-input');
      input.value = '  New Title  ';
      lib.submitRename();
      const msg = sentMessages.find(m => m.message === 'LIBRARY_RENAME');
      expect(msg).toBeDefined();
      expect(msg.contents).toEqual({ conversation_id: 'c1', title: 'New Title' });
    });

    it('submitRename refuses to send a blank title', () => {
      const input = document.getElementById('library-viewer-rename-input');
      input.value = '   ';
      lib.submitRename();
      expect(sentMessages.find(m => m.message === 'LIBRARY_RENAME')).toBeUndefined();
    });

    it('handleRenamedMessage patches local state and updates the viewer header', () => {
      lib.handleRenamedMessage({ res: 'success', conversation_id: 'c1', title: 'New Title' });
      const titleEl = document.getElementById('library-viewer-title');
      expect(titleEl.textContent).toBe('New Title');
      expect(lib._state.allRows[0].title).toBe('New Title');
    });

    it('handleRenamedMessage on failure does not mutate local state', () => {
      lib.handleRenamedMessage({ res: 'failure', content: 'oops', conversation_id: 'c1' });
      expect(lib._state.allRows[0].title).toBe('Old Title');
    });
  });

  describe('app capability classes', () => {
    afterEach(() => {
      delete window.apps;
      delete window.params;
    });

    function setApp(name, settings) {
      window.apps = {};
      window.apps[name] = settings || {};
      window.params = { app_name: name };
    }

    it('updateCapabilityClasses delegates to applyAppCapabilityClasses with the current app name', () => {
      const spy = jest.fn();
      window.applyAppCapabilityClasses = spy;
      try {
        setApp('SecondOpinionOpenAI', { library_search: false });
        lib.updateCapabilityClasses();
        expect(spy).toHaveBeenLastCalledWith('SecondOpinionOpenAI');

        setApp('ChatOpenAI', { library_search: true });
        lib.updateCapabilityClasses();
        expect(spy).toHaveBeenLastCalledWith('ChatOpenAI');
      } finally {
        delete window.applyAppCapabilityClasses;
      }
    });
  });

  describe('privacyBadgeHtml', () => {
    // Privacy Filter and KB save are mutually exclusive at the app
    // level, so saved KB entries never carry a `pii_status` flag. The
    // remaining badge is a heuristic for legacy entries whose title /
    // source obviously matches an email or phone-number pattern.

    it('emits a muted warning when title looks like PII (email pattern)', () => {
      const html = lib.privacyBadgeHtml({ title: 'Email alice@example.com about the project' });
      expect(html).toMatch(/text-secondary/);
      expect(html).toMatch(/fa-triangle-exclamation/);
    });

    it('emits no badge when there is no signal at all', () => {
      const html = lib.privacyBadgeHtml({ title: 'Project kickoff notes' });
      expect(html).toBe('');
    });

    it('detects phone-number patterns in title', () => {
      const html = lib.privacyBadgeHtml({ title: 'Call 03-1234-5678 tomorrow' });
      expect(html).toMatch(/fa-triangle-exclamation/);
    });
  });
});
