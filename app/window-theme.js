// Marks <html> with dark-theme or light-theme, the classes the Web UI uses, so
// the dark values in tokens.css apply here too. Light or dark comes from
// Electron (prefers-color-scheme follows the app's theme setting; see
// theme_sync.js). Run in <head>, before the page is first drawn.
(function () {
  const query = window.matchMedia('(prefers-color-scheme: dark)');
  function mark() {
    const dark = query.matches;
    document.documentElement.classList.toggle('dark-theme', dark);
    document.documentElement.classList.toggle('light-theme', !dark);
  }
  mark();
  query.addEventListener('change', mark);
})();
