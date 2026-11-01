// A small window whose page reports the height its content needs (translated
// titles and hints wrap) takes that height before it is shown. Reports from
// any other page are ignored, and the height is kept within bounds.
function createFitHandler(win, { width, min = 160, max = 640, onFitted }) {
  return function onFit(event, height) {
    if (win.isDestroyed() || event.sender !== win.webContents) return;
    const h = Math.round(Number(height));
    if (Number.isFinite(h) && h > 0) win.setContentSize(width, Math.min(Math.max(h, min), max));
    onFitted();
  };
}

module.exports = { createFitHandler };
