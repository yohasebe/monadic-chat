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
      expect(out).toBe('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;&amp;&#39;');
    });

    it('coerces null / undefined into the empty string', () => {
      expect(lib.escapeHtml(null)).toBe('');
      expect(lib.escapeHtml(undefined)).toBe('');
    });
  });

  describe('scopeBadge', () => {
    it('renders Global as the green badge with label "Global"', () => {
      const html = lib.scopeBadge('Global');
      expect(html).toContain('mc-badge--green');
      expect(html).toContain('Global');
    });
    it('renders an app-class scope as a muted badge with the formatted name', () => {
      const html = lib.scopeBadge('ChatOpenAI');
      expect(html).toContain('mc-badge--grey');
      expect(html).toContain('Chat (OpenAI)');
    });
    it('treats nil/empty as Global', () => {
      expect(lib.scopeBadge(undefined)).toContain('Global');
      expect(lib.scopeBadge('')).toContain('Global');
    });
  });

  describe('formatScopeApp', () => {
    it('returns Global for the literal sentinel', () => {
      expect(lib.formatScopeApp('Global')).toBe('Global');
    });
    it('splits ChatOpenAI into "Chat (OpenAI)"', () => {
      expect(lib.formatScopeApp('ChatOpenAI')).toBe('Chat (OpenAI)');
    });
    it('splits multi-word app names with provider suffix', () => {
      expect(lib.formatScopeApp('JupyterNotebookGrok')).toBe('Jupyter Notebook (Grok)');
      expect(lib.formatScopeApp('KnowledgeBaseDeepSeek')).toBe('Knowledge Base (DeepSeek)');
    });
    it('passes through scopes without a known provider suffix', () => {
      expect(lib.formatScopeApp('CustomThing')).toBe('CustomThing');
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
          language: 'en', scope_app: 'Global', turns_count: 12,
          messages_count: 12, created_at: new Date().toISOString()
        },
        {
          conversation_id: 'B', title: '', source: 'monadic-chat',
          language: 'ja', scope_app: 'ChatOpenAI', turns_count: 4,
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
        scope_app: 'ChatOpenAI', created_at: new Date().toISOString()
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
        { conversation_id: 'conv-1', title: 'first', scope_app: 'ChatOpenAI' },
        { conversation_id: 'conv-2', title: 'second', scope_app: 'Global' }
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
    it('renders a single-line summary with per-scope counts (Global first)', () => {
      const out = lib.formatStats({
        conversations_total: 5,
        conversations_by_scope: { Global: 2, ChatOpenAI: 2, KnowledgeBaseClaude: 1 }
      });
      expect(out).toBe(
        'Knowledge Base: 5 total — Global 2, Chat (OpenAI) 2, Knowledge Base (Claude) 1'
      );
    });

    it('renders a bare total when no per-scope data is present', () => {
      const out = lib.formatStats({ conversations_total: 7 });
      expect(out).toBe('Knowledge Base: 7 total');
    });

    it('returns the empty string for nullish input', () => {
      expect(lib.formatStats(null)).toBe('');
    });
  });

  describe('openSaveModal title pre-fill', () => {
    afterEach(() => {
      document.body.innerHTML = '';
      lib._state.currentConversationId = null;
      lib._state.allRows = [];
      lib._state.cachedTitleSuggestion = null;
      lib._state.cachedTitleSuggestionMessageCount = 0;
    });

    function setupModal() {
      document.body.innerHTML = `
        <div id="librarySaveModal">
          <input id="library-save-title">
          <span id="library-save-title-spinner" style="display:none"></span>
          <input id="library-scope-app" type="radio" name="s" value="app">
          <input id="library-scope-global" type="radio" name="s" value="Global">
          <span id="library-scope-app-name"></span>
          <div id="library-save-privacy-note" style="display:none"></div>
          <div id="library-save-update-note" style="display:none"></div>
          <span id="library-save-modal-title-text"></span>
          <span id="library-save-confirm-text"></span>
        </div>`;
    }

    it('blanks the title field on first save (no sticky id)', () => {
      setupModal();
      lib.openSaveModal();
      expect(document.getElementById('library-save-title').value).toBe('');
    });

    it('refuses to open the modal when the session has no messages', () => {
      // Defence-in-depth check: the Save button is disabled when
      // window.messages is empty, but openSaveModal is also exposed on
      // window.libraryPanel so a programmatic caller could try to open
      // it directly. The guard inside openSaveModal must short-circuit
      // and surface a warning rather than silently producing an empty
      // Knowledge Base entry.
      setupModal();
      global.window.messages = [];
      const flashed = [];
      const originalSetAlert = global.window.setAlert;
      global.window.setAlert = (msg, kind) => flashed.push({ msg, kind });
      try {
        const before = document.getElementById('library-save-title').value;
        lib.openSaveModal();
        // Title input remains untouched; the modal-open side effects
        // (placeholder, scope selection, etc.) are skipped.
        expect(document.getElementById('library-save-title').value).toBe(before);
        // A user-visible warning is queued.
        expect(flashed.length).toBe(1);
        expect(flashed[0].kind).toBe('warning');
        expect(flashed[0].msg).toMatch(/no messages/i);
      } finally {
        global.window.setAlert = originalSetAlert;
      }
    });

    it('pre-fills the latest known title when re-saving the same conversation', () => {
      setupModal();
      // openSaveModal now refuses empty sessions up front (the Save button
      // is also disabled when there are no messages), so a re-save scenario
      // must include at least one user/assistant message to exercise the
      // pre-fill branch.
      global.window.messages = [{ role: 'user', text: 'continued', mid: 2 }];
      lib._state.currentConversationId = 'conv-9';
      lib._state.allRows = [
        { conversation_id: 'conv-9', title: 'My renamed conversation' },
        { conversation_id: 'other', title: 'Unrelated' }
      ];
      lib.openSaveModal();
      // After Rename in the Viewer the row's title is updated in-place,
      // so the next openSaveModal must surface that title rather than
      // dropping back to the empty default.
      expect(document.getElementById('library-save-title').value)
        .toBe('My renamed conversation');
    });

    it('still blanks the title when the sticky id is unknown to the inventory', () => {
      // Defensive: if the row was deleted out from under us, fall back
      // to the blank default so the user can type a fresh title.
      setupModal();
      lib._state.currentConversationId = 'gone';
      lib._state.allRows = [];
      lib.openSaveModal();
      expect(document.getElementById('library-save-title').value).toBe('');
    });

    it('requests an LLM title suggestion on first save with conversation content', () => {
      setupModal();
      global.window.messages = [
        { role: 'system', text: 'sys', mid: 1 },
        { role: 'user', text: 'Help me write Ruby.', mid: 2 },
        { role: 'assistant', text: 'Sure, what specifically?', mid: 3 }
      ];
      const before = sentMessages.length;
      lib.openSaveModal();
      const newSends = sentMessages.slice(before);
      const req = newSends.find(m => m.message === 'LIBRARY_SUGGEST_TITLE');
      expect(req).toBeDefined();
      expect(req.contents.messages).toEqual([
        { role: 'system', text: 'sys' },
        { role: 'user', text: 'Help me write Ruby.' },
        { role: 'assistant', text: 'Sure, what specifically?' }
      ]);
      expect(lib._state.titleSuggestionPending).toBe(true);
    });

    it('does not request a suggestion on re-save (sticky id present)', () => {
      setupModal();
      lib._state.currentConversationId = 'sticky-1';
      lib._state.allRows = [{ conversation_id: 'sticky-1', title: 'Existing' }];
      global.window.messages = [{ role: 'user', text: 'Help.' }];
      const before = sentMessages.length;
      lib.openSaveModal();
      const newSends = sentMessages.slice(before);
      expect(newSends.find(m => m.message === 'LIBRARY_SUGGEST_TITLE')).toBeUndefined();
    });

    it('does not request a suggestion when there is no conversation content', () => {
      setupModal();
      global.window.messages = [];
      const before = sentMessages.length;
      lib.openSaveModal();
      const newSends = sentMessages.slice(before);
      expect(newSends.find(m => m.message === 'LIBRARY_SUGGEST_TITLE')).toBeUndefined();
    });

    it('reuses a cached suggestion when the conversation has not grown', () => {
      // First open: no cache, request fires.
      setupModal();
      global.window.messages = [
        { role: 'user', text: 'Hi.' },
        { role: 'assistant', text: 'Hello!' }
      ];
      lib._state.cachedTitleSuggestion = 'Cached topic';
      lib._state.cachedTitleSuggestionMessageCount = 2;

      const before = sentMessages.length;
      lib.openSaveModal();
      const newSends = sentMessages.slice(before);
      // Cache hit: no LIBRARY_SUGGEST_TITLE traffic.
      expect(newSends.find(m => m.message === 'LIBRARY_SUGGEST_TITLE')).toBeUndefined();
      expect(document.getElementById('library-save-title').value).toBe('Cached topic');
      expect(lib._state.titleSuggestionPending).toBe(false);
    });

    it('refreshes the suggestion when new conversation turns have been added', () => {
      setupModal();
      lib._state.cachedTitleSuggestion = 'Stale title';
      lib._state.cachedTitleSuggestionMessageCount = 2;
      // Conversation grew from 2 to 4 turns — cached title is no longer
      // representative of the latest exchange, so we re-ask.
      global.window.messages = [
        { role: 'user', text: 'Hi.' },
        { role: 'assistant', text: 'Hello!' },
        { role: 'user', text: 'Tell me more.' },
        { role: 'assistant', text: 'Sure.' }
      ];

      const before = sentMessages.length;
      lib.openSaveModal();
      const newSends = sentMessages.slice(before);
      expect(newSends.find(m => m.message === 'LIBRARY_SUGGEST_TITLE')).toBeDefined();
      // Title field stays empty until the response arrives — we did
      // not pre-fill it with the stale cached value.
      expect(document.getElementById('library-save-title').value).toBe('');
    });
  });

  describe('handleTitleSuggested', () => {
    afterEach(() => {
      document.body.innerHTML = '';
      lib._state.titleSuggestionPending = false;
    });

    it('writes the suggestion into the title field when the user has not typed', () => {
      document.body.innerHTML = '<input id="library-save-title" value="" placeholder="Suggesting title…">';
      lib._state.titleSuggestionPending = true;
      lib.handleTitleSuggested({ res: 'success', title: 'Ruby refactor questions' });
      expect(document.getElementById('library-save-title').value).toBe('Ruby refactor questions');
      expect(lib._state.titleSuggestionPending).toBe(false);
    });

    it('leaves the title alone if the user already typed something (race protection)', () => {
      document.body.innerHTML = '<input id="library-save-title" value="My own title">';
      lib._state.titleSuggestionPending = true;
      lib.handleTitleSuggested({ res: 'success', title: 'Suggested name' });
      expect(document.getElementById('library-save-title').value).toBe('My own title');
    });

    it('clears the spinner placeholder on failure without surfacing an error', () => {
      document.body.innerHTML = '<input id="library-save-title" value="" placeholder="Suggesting title…">';
      lib._state.titleSuggestionPending = true;
      lib.handleTitleSuggested({ res: 'failure' });
      expect(document.getElementById('library-save-title').value).toBe('');
      expect(document.getElementById('library-save-title').placeholder).not.toBe('Suggesting title…');
      expect(lib._state.titleSuggestionPending).toBe(false);
    });

    it('hides the inline spinner once a response arrives (success or failure)', () => {
      document.body.innerHTML = `
        <input id="library-save-title" value="" placeholder="Suggesting title…">
        <span id="library-save-title-spinner" style="display: ;"></span>`;
      lib._state.titleSuggestionPending = true;
      lib.handleTitleSuggested({ res: 'failure' });
      expect(document.getElementById('library-save-title-spinner').style.display).toBe('none');

      // Even on success the spinner should still be cleared so it does
      // not linger above the just-written title.
      document.getElementById('library-save-title-spinner').style.display = '';
      lib._state.titleSuggestionPending = true;
      lib.handleTitleSuggested({ res: 'success', title: 'X' });
      expect(document.getElementById('library-save-title-spinner').style.display).toBe('none');
    });

    it('caches a successful suggestion against the current message count', () => {
      document.body.innerHTML = '<input id="library-save-title" value="">';
      global.window.messages = [
        { role: 'user', text: 'Hi.' },
        { role: 'assistant', text: 'Hello!' }
      ];
      lib._state.titleSuggestionPending = true;
      lib.handleTitleSuggested({ res: 'success', title: 'Greetings' });
      expect(lib._state.cachedTitleSuggestion).toBe('Greetings');
      expect(lib._state.cachedTitleSuggestionMessageCount).toBe(2);
    });
  });

  describe('clearCurrentConversation cache hygiene', () => {
    it('wipes the cached suggestion alongside the sticky id', () => {
      lib._state.currentConversationId = 'conv-1';
      lib._state.cachedTitleSuggestion = 'Old title';
      lib._state.cachedTitleSuggestionMessageCount = 4;
      lib.clearCurrentConversation();
      expect(lib._state.currentConversationId).toBeNull();
      expect(lib._state.cachedTitleSuggestion).toBeNull();
      expect(lib._state.cachedTitleSuggestionMessageCount).toBe(0);
    });
  });

  describe('readModalSelections', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('returns title text and chosen scope', () => {
      document.body.innerHTML = `
        <input id="library-save-title" value="My Conversation">
        <input type="radio" name="librarySaveScope" value="app">
        <input type="radio" name="librarySaveScope" value="Global" checked>
      `;
      // Privacy Filter and KB save are mutually exclusive at the app
      // level; the Save button is hidden in PF apps so anonymize / pf
      // gating no longer flows through readModalSelections.
      expect(lib.readModalSelections()).toEqual({ title: 'My Conversation', scopeApp: 'Global' });
    });

    it('defaults to "app" when no radio is checked', () => {
      document.body.innerHTML = '<input id="library-save-title" value="">';
      expect(lib.readModalSelections()).toEqual({ title: '', scopeApp: 'app' });
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
      const payload = lib.buildSavePayload({ title: '  Demo  ', scopeApp: 'app' });
      expect(payload.parameters.app_name).toBe('ChatOpenAI');
      expect(payload.parameters.initiate_from_assistant).toBeUndefined();
      // The "app" sentinel means "let the server scope to params.app_name".
      // We omit scope_app from the payload so it stays implicit.
      expect(payload.scope_app).toBeUndefined();
      expect(payload.title).toBe('Demo');
      expect(payload.messages.length).toBe(3);
      expect(payload.messages[0].role).toBe('system');
      expect(payload.messages[0].text).toBe('You are a helper.');
      expect(payload.messages[1]).toMatchObject({ role: 'user', text: 'Hi' });
      expect(payload.messages[2]).toMatchObject({ role: 'assistant', text: 'Hello!', thinking: 'reasoning text' });
    });

    it('forwards an explicit Global scope into the payload', () => {
      const payload = lib.buildSavePayload({ scopeApp: 'Global', monadicState: { foo: 1 } });
      expect(payload.monadic_state).toEqual({ foo: 1 });
      expect(payload.scope_app).toBe('Global');
    });

    it('omits an empty title from the payload', () => {
      const payload = lib.buildSavePayload({ title: '   ', scopeApp: 'app' });
      expect(payload.title).toBeUndefined();
    });
  });

  describe('handleConversations / handleStats / handleSavedMessage', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('renders compact inventory rows into #library-recent on library_conversations', () => {
      document.body.innerHTML = '<div id="library-recent"></div>'
        + '<span id="library-total-badge"></span>';
      lib.handleConversations({ content: [
        { conversation_id: 'A', title: 'Alpha', scope_app: 'ChatOpenAI',
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
        conversation_id: 'C' + i, title: 'Conv ' + i, scope_app: 'ChatOpenAI',
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
      lib.handleStats({ content: {
        conversations_total: 4,
        conversations_by_scope: { Global: 1, ChatOpenAI: 3 }
      }});
      expect(document.getElementById('library-stats-info').textContent)
        .toBe('Knowledge Base: 4 total — Global 1, Chat (OpenAI) 3');
    });

    it('refreshes list and stats after a successful save', () => {
      lib.handleSavedMessage({ res: 'success', conversation_id: 'X', scope_app: 'ChatOpenAI' });
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

    it('remembers conversation_id on save success so the next save updates in place', () => {
      lib._state.currentConversationId = null;
      lib.handleSavedMessage({ res: 'success', conversation_id: 'sticky-1' });
      expect(lib._state.currentConversationId).toBe('sticky-1');

      // buildSavePayload now ships the sticky id back so the server can
      // delete-then-insert.
      const payload = lib.buildSavePayload({});
      expect(payload.conversation_id).toBe('sticky-1');
    });

    it('clearCurrentConversation drops the binding (Reset / app switch hook)', () => {
      lib._state.currentConversationId = 'sticky-9';
      lib.clearCurrentConversation();
      expect(lib._state.currentConversationId).toBeNull();
      const payload = lib.buildSavePayload({});
      expect(payload.conversation_id).toBeUndefined();
    });

    it('drops the binding when the matching entry is deleted from Browse', () => {
      lib._state.currentConversationId = 'sticky-1';
      lib._state.allRows = [
        { conversation_id: 'sticky-1', title: 'A' },
        { conversation_id: 'other', title: 'B' }
      ];
      lib.handleDeletedMessage({ res: 'success', conversation_id: 'sticky-1' });
      expect(lib._state.currentConversationId).toBeNull();
    });

    it('keeps the binding when an unrelated entry is deleted', () => {
      lib._state.currentConversationId = 'sticky-1';
      lib._state.allRows = [
        { conversation_id: 'sticky-1', title: 'A' },
        { conversation_id: 'other', title: 'B' }
      ];
      lib.handleDeletedMessage({ res: 'success', conversation_id: 'other' });
      expect(lib._state.currentConversationId).toBe('sticky-1');
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
        conversation_id: 'X', title: 'Hello world', scope_app: 'Global',
        turns_count: 7, created_at: new Date().toISOString()
      });
      expect(html).toContain('library-row-compact');
      expect(html).toContain('library-scope-dot');
      expect(html).toContain('Hello world');
      expect(html).toContain('7T');
      // No inline delete button in compact row — actions live in browse modal.
      expect(html).not.toContain('library-row-delete');
    });

    it('truncates very long titles', () => {
      const longTitle = 'a'.repeat(100);
      const html = lib.compactRowMarkup({
        conversation_id: 'X', title: longTitle, scope_app: 'ChatOpenAI',
        turns_count: 1, created_at: new Date().toISOString()
      });
      expect(html).toContain('…');
    });
  });

  describe('browseRowMarkup', () => {
    it('uses 3 inline icon buttons instead of a dropdown menu', () => {
      const html = lib.browseRowMarkup({
        conversation_id: 'X', title: 'T', scope_app: 'ChatOpenAI',
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

    it('flips the toggle target scope based on the current value', () => {
      var prevParams = window.params;
      window.params = { app_name: 'ChatClaude' };
      try {
        var appOnlyRow = lib.browseRowMarkup({
          conversation_id: 'A', title: 'A', scope_app: 'ChatOpenAI', turns_count: 1,
          created_at: new Date().toISOString()
        }, 0);
        expect(appOnlyRow).toContain('data-next-scope="Global"');

        var globalRow = lib.browseRowMarkup({
          conversation_id: 'B', title: 'B', scope_app: 'Global', turns_count: 1,
          created_at: new Date().toISOString()
        }, 1);
        expect(globalRow).toContain('data-next-scope="ChatClaude"');
      } finally {
        window.params = prevParams;
      }
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

    it('applyFilters narrows by scope and search term', () => {
      lib._state.allRows = seedRows(20);
      lib._state.scopeFilter = 'Global';
      lib._state.searchTerm = '';
      lib.applyFilters();
      expect(lib._state.filteredRows.every(r => r.scope_app === 'Global')).toBe(true);

      lib._state.scopeFilter = 'all';
      lib._state.searchTerm = 'talk 1'; // matches Talk 1, 10..19
      lib.applyFilters();
      expect(lib._state.filteredRows.length).toBe(11);
    });

    it('applyFilters sorts by created_desc by default', () => {
      lib._state.allRows = seedRows(5);
      lib._state.searchTerm = '';
      lib._state.scopeFilter = 'all';
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
      lib._state.scopeFilter = 'all';
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
      lib._state.scopeFilter = 'Global';  // now ~15 rows → 1 page
      lib._state.searchTerm = '';
      lib.applyFilters();
      expect(lib._state.page).toBe(0);
    });
  });

  describe('handleScopeUpdated', () => {
    afterEach(() => { document.body.innerHTML = ''; });

    it('updates the cached row scope_app on success and triggers stats refresh', () => {
      document.body.innerHTML = '<div id="library-recent"></div>'
        + '<span id="library-total-badge"></span>';
      lib.handleConversations({ content: [
        { conversation_id: 'X', title: 'T', scope_app: 'ChatOpenAI',
          turns_count: 1, created_at: new Date().toISOString() }
      ] });
      const before = sentMessages.length;
      lib.handleScopeUpdated({ res: 'success', conversation_id: 'X', scope_app: 'Global' });
      expect(lib._state.allRows.find(r => r.conversation_id === 'X').scope_app).toBe('Global');
      expect(sentMessages.slice(before).some(m => m.message === 'LIBRARY_STATS')).toBe(true);
    });

    it('does not mutate cache on failure', () => {
      lib._state.allRows = [{ conversation_id: 'X', scope_app: 'ChatOpenAI' }];
      lib.handleScopeUpdated({ res: 'failure', conversation_id: 'X', content: 'qdrant down' });
      expect(lib._state.allRows[0].scope_app).toBe('ChatOpenAI');
    });
  });

  describe('setScopeApp / browse action menu', () => {
    it('setScopeApp sends LIBRARY_SET_SCOPE with conversation_id+scope_app', () => {
      lib.setScopeApp('conv-9', 'Global');
      const msg = sentMessages.find(m => m.message === 'LIBRARY_SET_SCOPE');
      expect(msg).toBeDefined();
      expect(msg.contents).toEqual({ conversation_id: 'conv-9', scope_app: 'Global' });
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
      const out = await lib.uploadLibraryFile(file, { title: 'Paper', scopeApp: 'Global' });
      expect(captured.url).toBe('/library/import');
      expect(captured.opts.method).toBe('POST');
      expect(captured.opts.body instanceof FormData).toBe(true);
      expect(captured.opts.body.get('libraryFile')).toBe(file);
      expect(captured.opts.body.get('libraryTitle')).toBe('Paper');
      expect(captured.opts.body.get('libraryScopeApp')).toBe('Global');
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

  describe('per-app KB feature gates', () => {
    afterEach(() => {
      document.body.innerHTML = '';
      delete window.apps;
      delete window.params;
    });

    function setApp(name, settings) {
      window.apps = {};
      window.apps[name] = settings || {};
      window.params = { app_name: name };
    }

    it('isCurrentAppKbSaveEligible returns false for apps with library_save: false', () => {
      setApp('ChatPlusOpenAI', { library_save: false, library_search: false, privacy_enabled: true });
      expect(lib.isCurrentAppKbSaveEligible()).toBe(false);
    });

    it('isCurrentAppKbSaveEligible returns true for apps with library_save: true', () => {
      setApp('ChatOpenAI', { library_save: true, library_search: true });
      expect(lib.isCurrentAppKbSaveEligible()).toBe(true);
    });

    it('isCurrentAppKbRetrievalEligible returns false when library_search is false (PF-only and artifact apps)', () => {
      setApp('ChatPlusOpenAI', { library_save: false, library_search: false, privacy_enabled: true });
      expect(lib.isCurrentAppKbRetrievalEligible()).toBe(false);
    });

    it('isCurrentAppKbRetrievalEligible returns true when library_search is true (KB-only apps)', () => {
      setApp('ChatOpenAI', { library_save: true, library_search: true });
      expect(lib.isCurrentAppKbRetrievalEligible()).toBe(true);
    });

    it('updateRagToggleVisibility delegates to applyAppCapabilityClasses with the current app name', () => {
      // Phase 4: visibility moved from JS-driven `style.display` to a body
      // class + CSS gate. updateRagToggleVisibility now exists only to fan
      // the SessionState `app:changed` path into the SSOT entry point in
      // monadic.js (applyAppCapabilityClasses), which toggles the body
      // class. The CSS rule `body:not(.app-cap-kb-search) #library-rag-toggle-row`
      // does the actual hiding.
      const spy = jest.fn();
      window.applyAppCapabilityClasses = spy;
      try {
        setApp('ChatPlusOpenAI', { library_search: false });
        lib.updateRagToggleVisibility();
        expect(spy).toHaveBeenLastCalledWith('ChatPlusOpenAI');

        setApp('ChatOpenAI', { library_search: true });
        lib.updateRagToggleVisibility();
        expect(spy).toHaveBeenLastCalledWith('ChatOpenAI');
      } finally {
        delete window.applyAppCapabilityClasses;
      }
    });

    it('updateSaveButtonAvailability disables and explains when the app is ineligible', () => {
      // Save button is always present in the DOM (no display:none gate).
      // When the app does not support library_save (e.g. Chat Plus, which
      // declares `privacy do; enabled true; end`), the button stays
      // visible but disabled with a tooltip explaining why. This mirrors
      // the Privacy Filter session toggle's "visible but disabled"
      // pattern on apps that don't support PF.
      document.body.innerHTML = '<button id="library-save"></button>';
      const btn = document.getElementById('library-save');
      setApp('ChatPlusOpenAI', { library_save: false });
      lib.updateSaveButtonAvailability();
      expect(btn.disabled).toBe(true);
      // Tooltip should reference the "app does not support saving" reason,
      // not the no-messages or privacy-active reasons.
      expect(btn.getAttribute('title')).toMatch(/does not support|サポート/i);
    });

    it('updateSaveButtonAvailability disables with privacy-active tooltip when Privacy Filter is ON', () => {
      document.body.innerHTML = '<button id="library-save"></button>';
      const btn = document.getElementById('library-save');
      // Eligible app (library_save: true) so the privacy-active branch is reachable.
      setApp('ChatOpenAI', { library_save: true });
      // Force privacyOn() to return true via the window.privacyEnabled
      // fallback that the module reads when WsPrivacyHandler isn't loaded.
      const prev = window.privacyEnabled;
      window.privacyEnabled = true;
      try {
        lib.updateSaveButtonAvailability();
        expect(btn.disabled).toBe(true);
        expect(btn.getAttribute('title')).toMatch(/Privacy/i);
      } finally {
        window.privacyEnabled = prev;
      }
    });

    it('absent flag defaults to eligible (legacy / user-defined custom apps)', () => {
      setApp('CustomLegacyApp', {}); // no library_save / library_search
      expect(lib.isCurrentAppKbSaveEligible()).toBe(true);
      expect(lib.isCurrentAppKbRetrievalEligible()).toBe(true);
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
