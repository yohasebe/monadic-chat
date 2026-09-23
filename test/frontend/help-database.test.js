const fs = require('fs');
const path = require('path');

const ruby = path.resolve(__dirname, '../../docker/services/ruby');
const source = fs.readFileSync(path.join(ruby, 'public/js/monadic/help-database.js'), 'utf8');
const template = fs.readFileSync(path.join(ruby, 'views/_help_database_panel.erb'), 'utf8');
const $ = id => document.getElementById(id);
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };

function mount(standalone = false) {
  document.body.innerHTML = template
    .replace('<%= standalone %>', String(standalone))
    .replace("<%= 'hidden' unless standalone %>", standalone ? '' : 'hidden');
  window.eval(fs.readFileSync(path.join(ruby, 'public/js/monadic/dom-helpers.js'), 'utf8'));
  window.eval(source);
}

describe('Help data panel', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.spyOn(document, 'readyState', 'get').mockReturnValue('complete');
    window.webUIi18n = { t: key => key.replace('ui.helpData.', '') };
    window.monadicFetch = {
      getJson: jest.fn().mockResolvedValue({ state: 'not_installed', searchable: false }),
      postJson: jest.fn().mockResolvedValue({ accepted: true, state: 'installing' })
    };
  });

  afterEach(() => {
    jest.clearAllTimers();
    jest.useRealTimers();
    jest.restoreAllMocks();
    document.body.innerHTML = '';
    delete window.HelpDatabase;
  });

  test.each([
    ['not_installed', 'install'], ['update_available', 'update'], ['legacy', 'reinstall'],
    ['failed', 'retry'], ['installed', null], ['installing', null], ['unavailable', null]
  ])('renders %s with the appropriate action', async (state, action) => {
    window.monadicFetch.getJson.mockResolvedValue({ state, reason: state === 'failed' ? 'Count mismatch' : '' });
    mount();
    window.HelpDatabase.setApp('MonadicHelpOpenAI');
    await flush();
    expect($('help-database-panel').hidden).toBe(false);
    expect($('help-database-status').textContent).toBe(state);
    expect($('help-database-install').hidden).toBe(!action);
    expect($('help-database-install').disabled).toBe(!action);
    if (action) expect($('help-database-install').textContent).toBe(action);
    if (state === 'failed') expect($('help-database-reason').textContent).toBe('Count mismatch');
    expect(window.monadicFetch.postJson).not.toHaveBeenCalled();
  });

  test.each(['validating', 'preparing', 'loading', 'verifying'])('shows %s progress', async stage => {
    window.monadicFetch.getJson.mockResolvedValue({ state: 'installing', progress: { stage, processed: 2, total: 5 } });
    mount(true);
    await flush();
    expect($('help-database-progress').textContent).toBe(stage === 'loading' ? 'loading: 2 / 5' : stage);
    expect($('help-database-install').disabled).toBe(true);
  });

  test('opens standalone management without any app or API key selection', async () => {
    mount(true);
    await flush();
    expect(window.monadicFetch.getJson).toHaveBeenCalledWith('/help/database/status');
    expect($('help-database-install').disabled).toBe(false);
    window.HelpDatabase.setApp('ChatOpenAI');
    expect($('help-database-panel').hidden).toBe(false);
  });

  test('uses the real translations on the standalone page and preserves status on a language change', async () => {
    mount(true);
    window.eval(fs.readFileSync(path.join(ruby, 'public/js/monadic/dom-helpers.js'), 'utf8'));
    window.eval(fs.readFileSync(path.join(ruby, 'public/js/i18n/translations.js'), 'utf8'));
    await window.i18nReady;
    await flush();
    expect($('help-database-status').textContent).toBe('Help data is not installed.');
    window.webUIi18n.setLanguage('ja');
    expect($('help-database-status').textContent).toBe(window.webUIi18n.t('ui.helpData.not_installed'));
    expect($('help-database-install').textContent).toBe(window.webUIi18n.t('ui.helpData.install'));
    expect($('help-database-status').textContent).not.toBe(window.webUIi18n.t('ui.helpData.checking'));
  });

  test('starts only on click, deduplicates clicks, and polls through completion', async () => {
    mount(true);
    await flush();
    let accept;
    window.monadicFetch.postJson.mockImplementation(() => new Promise(resolve => { accept = resolve; }));
    $('help-database-install').click();
    $('help-database-install').click();
    expect(window.monadicFetch.postJson).toHaveBeenCalledTimes(1);
    expect(window.monadicFetch.postJson).toHaveBeenCalledWith('/help/database/install');
    expect($('help-database-install').disabled).toBe(true);
    window.monadicFetch.getJson.mockResolvedValue({ state: 'installing', progress: { stage: 'loading', processed: 4, total: 5 } });
    accept({ accepted: true });
    await flush();
    expect($('help-database-progress').textContent).toBe('loading: 4 / 5');
    window.monadicFetch.getJson.mockResolvedValue({ state: 'installed', searchable: true });
    await jest.advanceTimersByTimeAsync(500);
    expect($('help-database-status').textContent).toBe('installed');
    expect($('help-database-install').hidden).toBe(true);
  });

  test('handles retryable busy without automatically sending another POST', async () => {
    mount(true);
    await flush();
    window.monadicFetch.postJson.mockRejectedValue({ status: 409, body: { state: 'busy', retryable: true } });
    $('help-database-install').click();
    await flush();
    expect($('help-database-notice').textContent).toBe('busy');
    expect($('help-database-install').disabled).toBe(false);
    await jest.advanceTimersByTimeAsync(5000);
    expect(window.monadicFetch.postJson).toHaveBeenCalledTimes(1);
  });

  test('recovers from a connection error on refresh', async () => {
    window.monadicFetch.getJson.mockRejectedValue(new Error('offline'));
    mount(true);
    await flush();
    expect($('help-database-status').textContent).toBe('unavailable');
    expect($('help-database-install').hidden).toBe(true);
    window.monadicFetch.getJson.mockResolvedValue({ state: 'not_installed' });
    $('help-database-refresh').click();
    await flush();
    expect($('help-database-install').disabled).toBe(false);
  });

  test('shows start errors and permits a user retry', async () => {
    mount(true);
    await flush();
    window.monadicFetch.postJson.mockRejectedValue(new Error('offline'));
    $('help-database-install').click();
    await flush();
    expect($('help-database-notice').textContent).toBe('startFailed');
    expect($('help-database-install').disabled).toBe(false);
  });

  test('renders failure reasons as text', async () => {
    const reason = '<img src=x onerror=alert(1)>';
    window.monadicFetch.getJson.mockResolvedValue({ state: 'failed', reason });
    mount(true);
    await flush();
    expect($('help-database-reason').textContent).toBe(reason);
    expect($('help-database-reason').querySelector('img')).toBeNull();
  });

  test('discards stale status responses and stops polling when switching away', async () => {
    let oldResponse;
    window.monadicFetch.getJson.mockImplementationOnce(() => new Promise(resolve => { oldResponse = resolve; }));
    mount();
    window.HelpDatabase.setApp('MonadicHelpOpenAI');
    window.HelpDatabase.setApp('ChatOpenAI');
    window.monadicFetch.getJson.mockResolvedValue({ state: 'installed' });
    window.HelpDatabase.setApp('MonadicHelpOpenAI');
    await flush();
    oldResponse({ state: 'failed' });
    await flush();
    expect($('help-database-status').textContent).toBe('installed');
    window.HelpDatabase.setApp('ChatOpenAI');
    const requests = window.monadicFetch.getJson.mock.calls.length;
    await jest.advanceTimersByTimeAsync(10000);
    expect($('help-database-panel').hidden).toBe(true);
    expect(window.monadicFetch.getJson).toHaveBeenCalledTimes(requests);
  });

  test('updates on initial session restoration through the real proceedWithAppChange hook without a change event', async () => {
    mount();
    window.eval(fs.readFileSync(path.join(ruby, 'public/js/monadic/dom-helpers.js'), 'utf8'));
    const main = fs.readFileSync(path.join(ruby, 'public/js/monadic.js'), 'utf8');
    const applyApp = main.match(/window\.proceedWithAppChange = function proceedWithAppChange\(appValue\) \{[\s\S]*?\n  \}/)[0];
    window.initialAppLoaded = false;
    window.isLoadingParams = false;
    window.isImporting = false;
    window.isProcessingImport = false;
    window.eval(`(function () {
      const apps = { MonadicHelpOpenAI: { group: 'OpenAI', description: '', initiate_from_assistant: true } };
      const params = {};
      const messages = [{ role: 'user', content: 'restored' }];
      let lastApp = 'MonadicHelpOpenAI';
      const getProviderFromGroup = () => 'openai';
      const loadParams = () => {};
      const updateAppSelectIcon = () => {};
      const getModelsForApp = () => [];
      const isParamBroadcastSuppressed = () => true;
      ${applyApp}
    })();`);
    window.proceedWithAppChange('MonadicHelpOpenAI');
    await flush();
    expect($('help-database-panel').hidden).toBe(false);
    expect(window.monadicFetch.getJson).toHaveBeenCalledTimes(1);
    // Re-applying an already loaded restored app takes the early-return path.
    window.initialAppLoaded = true;
    window.proceedWithAppChange('MonadicHelpOpenAI');
    await flush();
    expect(window.monadicFetch.getJson).toHaveBeenCalledTimes(2);
  });
});
