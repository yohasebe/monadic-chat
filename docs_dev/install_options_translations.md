# Install Options translations

This window is an HTML renderer (isolated from the main app) that renders a modal for optional components. Key points to keep it localized:

- The canonical strings live in `app/translations/*.json`, structured under `menu.installOptionsPanel` and `dialogs`.
- The renderer now calls `installOptionsAPI.getTranslations()` which funnels through `ipcMain.handle('get-install-options-translations')`. The handler reads the current language from the `i18n` singleton so it always matches the UI language.
- UI language changes (`change-ui-language` IPC) broadcast `ui-language-changed` to the Install Options window; the renderer refreshes its strings on that event.
- The panel no longer uses cookies or `navigator.language`; this avoids stale values when users switch languages mid-session.

## When updating strings
- Update `app/translations/en.json` and mirrored keys in `ja.json`, `zh.json`, `ko.json`, `es.json`, `fr.json`, `de.json`.
- Confirm the key lives under `menu.installOptionsPanel` (`categories`, `buttons`, `messages`). Dialog strings belong under `dialogs`.
- Run the window manually after switching the UI language in Settings to verify each locale.

## Related files
- Renderer logic: `app/installOptions.html`
- Preload bridge: `app/preload.js`
- Main process IPC: `app/main.js` (`get-install-options-translations`, `change-ui-language`)
