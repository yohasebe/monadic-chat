// Renderer-side helpers for the in-app updater UI.
//
// Kept in a standalone module so the DOM logic is unit-testable in isolation:
// the console renderer runs with nodeIntegration:false and loads this via a
// <script> tag (see index.html), exposing window.MonadicUpdateUI; Jest requires
// it directly via the module.exports guard at the bottom (mirrors the
// verify-render.js pattern on the web-UI side).

(function () {
  // Render/update a SINGLE download-progress line (text + bar) in place.
  // `host` is the console's HTML output container. On every progress tick the
  // same #update-progress-line element is updated rather than appended, so the
  // log shows one line whose percentage and bar advance instead of one new line
  // per milestone. Returns the line element (or null when host/data missing).
  function renderDownloadProgress(host, data) {
    if (!host || !data) return null;
    const raw = Number(data.percent);
    const percent = Math.max(0, Math.min(100, Math.round(isNaN(raw) ? 0 : raw)));
    const mbps = data.bytesPerSecond
      ? (Number(data.bytesPerSecond) / 1024 / 1024).toFixed(1)
      : null;
    const speed = mbps ? ` (${mbps} MB/s)` : '';

    let line = host.querySelector('#update-progress-line');
    if (!line) {
      line = document.createElement('div');
      line.id = 'update-progress-line';
      line.className = 'update-progress';
      host.appendChild(line);
    }
    // Create the label/bar once and update them in place on later ticks —
    // electron-updater emits progress many times per second, so per-tick node
    // churn is real. textContent for the label (no untrusted input), a native
    // <progress> element for the bar.
    let label = line.querySelector('.update-progress-label');
    let bar = line.querySelector('.update-progress-bar');
    if (!label || !bar) {
      label = document.createElement('span');
      label.className = 'update-progress-label';
      bar = document.createElement('progress');
      bar.className = 'update-progress-bar';
      bar.max = 100;
      line.replaceChildren(label, bar);
    }
    label.textContent = `Downloading update: ${percent}%${speed}`;
    bar.value = percent;
    // Mirror the value into the attribute: other console writes use
    // `innerHTML +=`, which reserializes and reparses the container — the
    // JS-set .value property would be lost, but the attribute survives.
    bar.setAttribute('value', String(percent));
    return line;
  }

  // Delegate clicks on any .mc-update-now button (rendered inside the
  // update-available message) to the provided API. Idempotent: the listener is
  // attached at most once per host so repeated init calls don't stack handlers.
  function attachUpdateButtonHandler(host, api) {
    if (!host || host._mcUpdateWired) return;
    host._mcUpdateWired = true;
    host.addEventListener('click', function (e) {
      const target = e && e.target;
      const btn = target && target.closest ? target.closest('.mc-update-now') : null;
      if (!btn || !api) return;
      // The button says "Download & Install", so start the download directly
      // when that API exists; fall back to re-checking (older preload) only if
      // it doesn't.
      if (typeof api.startUpdateDownload === 'function') {
        api.startUpdateDownload();
      } else if (typeof api.checkForUpdates === 'function') {
        api.checkForUpdates();
      }
    });
  }

  // Insert an inline "Download & Install" button at the end of a formatMessage
  // "<p> ... </p>" string, so the update-available console line shows the
  // button beside the text. Pure string transform (no DOM) so it is shared by
  // the main process (which builds the message) and unit-testable. The button
  // carries class .mc-update-now, which attachUpdateButtonHandler delegates to
  // the check-for-updates flow.
  function injectUpdateButton(baseHtml, label) {
    const safeLabel = String(label == null ? '' : label);
    const btn =
      ' <button class="mc-update-now" data-i18n-key="messages.downloadAndInstall" ' +
      'style="margin-left:10px;padding:3px 10px;border:none;border-radius:4px;' +
      'background:#FF7F07;color:#fff;cursor:pointer;font-size:0.85em;">' +
      '<i class="fa-solid fa-download"></i> ' + safeLabel + '</button>';
    // Insert before the final </p>; if the shape is unexpected, append instead.
    return /<\/p>\s*$/.test(baseHtml)
      ? baseHtml.replace(/<\/p>\s*$/, btn + '</p>')
      : baseHtml + btn;
  }

  if (typeof window !== 'undefined') {
    window.MonadicUpdateUI = { renderDownloadProgress, attachUpdateButtonHandler, injectUpdateButton };
  }
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { renderDownloadProgress, attachUpdateButtonHandler, injectUpdateButton };
  }
})();
