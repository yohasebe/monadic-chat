// How the settings window and the app read a setting that is on unless
// turned off: only "false" turns it off, whatever its case and spaces, the
// same rule the Ruby server applies (Library::InChats.on?).
(function (root) {
  function onUnlessFalse(value) {
    return String(value ?? '').trim().toLowerCase() !== 'false';
  }

  const api = { onUnlessFalse };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.settingValues = api;
})(typeof window !== 'undefined' ? window : null);
