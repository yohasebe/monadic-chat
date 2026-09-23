(function (window) {
  'use strict';

  let panel;
  let timer;
  let sequence = 0;
  let posting = false;
  let current = { state: 'checking' };

  function t(key) {
    return window.webUIi18n.t('ui.helpData.' + key);
  }

  function text(id, value) {
    const element = $id(id);
    if (!element) return;
    element.textContent = value || '';
    element.hidden = !value;
  }

  function render(snapshot) {
    current = snapshot;
    const states = ['not_installed', 'installing', 'installed', 'update_available', 'legacy', 'failed', 'unavailable', 'checking'];
    const state = states.includes(snapshot.state) ? snapshot.state : 'unavailable';
    panel.dataset.state = state;
    const status = $id('help-database-status');
    if (status) status.dataset.i18n = 'ui.helpData.' + state;
    text('help-database-status', t(state));
    const progress = snapshot.progress || {};
    const stages = ['validating', 'preparing', 'loading', 'verifying', 'completed'];
    let detail = state === 'installing' && stages.includes(progress.stage) ? t(progress.stage) : '';
    if (detail && progress.stage === 'loading' && Number.isFinite(progress.processed) && Number.isFinite(progress.total)) {
      detail += `: ${progress.processed} / ${progress.total}`;
    }
    text('help-database-progress', detail);
    const reason = state === 'failed' ? snapshot.reason :
      (snapshot.last_attempt && snapshot.last_attempt.state === 'failed' ? snapshot.last_attempt.reason : '');
    text('help-database-reason', reason);
    const action = { not_installed: 'install', update_available: 'update', legacy: 'reinstall', failed: 'retry' }[state];
    const button = $id('help-database-install');
    if (button) {
      button.hidden = !action;
      button.disabled = posting || !action;
      button.textContent = action ? t(action) : '';
      if (action) button.dataset.i18n = 'ui.helpData.' + action;
      else delete button.dataset.i18n;
    }
    const refreshButton = $id('help-database-refresh');
    if (refreshButton) refreshButton.disabled = posting;
  }

  async function refresh() {
    if (!panel || panel.hidden || posting) return;
    clearTimeout(timer);
    const request = ++sequence;
    let snapshot;
    try {
      snapshot = await window.monadicFetch.getJson('/help/database/status');
      if (!snapshot || typeof snapshot.state !== 'string') throw new Error('Invalid status');
    } catch (_) {
      snapshot = { state: 'unavailable', searchable: false };
    }
    if (request !== sequence || panel.hidden) return;
    render(snapshot);
    timer = setTimeout(refresh, snapshot.state === 'installing' ? 500 : 5000);
  }

  async function install() {
    const button = $id('help-database-install');
    if (posting || !button || button.disabled) return;
    posting = true;
    ++sequence;
    clearTimeout(timer);
    text('help-database-notice', '');
    render(current);
    try {
      const result = await window.monadicFetch.postJson('/help/database/install');
      if (!result.accepted) throw new Error('Installation was not accepted');
      render({ state: 'installing', progress: { stage: 'validating' } });
    } catch (error) {
      text('help-database-notice', t(error.status === 409 && error.body && error.body.retryable ? 'busy' : 'startFailed'));
    } finally {
      posting = false;
      render(current);
      await refresh();
    }
  }

  function setApp(appName) {
    if (!panel) init();
    if (!panel || panel.dataset.standalone === 'true') return;
    panel.hidden = appName !== 'MonadicHelpOpenAI';
    ++sequence;
    clearTimeout(timer);
    if (!panel.hidden) refresh();
  }

  function init() {
    if (panel) return;
    panel = $id('help-database-panel');
    if (!panel) return;
    $on($id('help-database-install'), 'click', install);
    $on($id('help-database-refresh'), 'click', () => {
      text('help-database-notice', '');
      refresh();
    });
    if (panel.dataset.standalone === 'true') refresh();
  }

  window.HelpDatabase = { setApp };
  if (document.readyState === 'loading') $on(document, 'DOMContentLoaded', init);
  else init();
})(window);
