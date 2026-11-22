/**
 * @jest-environment jsdom
 */
// The scripts the browser tool runs in a page (web_navigator.py), run here
// as written: what is typed in a password or another secret field is not
// given back to the tool.
const fs = require('fs');
const path = require('path');

const SOURCE = fs.readFileSync(
  path.join(__dirname, '../../docker/services/python/scripts/cli_tools/web_navigator.py'), 'utf8');

// The script of the function named, as the page runs it.
function scriptOf(functionName) {
  const start = SOURCE.indexOf(`def ${functionName}(`);
  if (start < 0) throw new Error(`no ${functionName} in web_navigator.py`);
  const open = SOURCE.indexOf('js = """', start);
  const close = SOURCE.indexOf('"""', open + 8);
  return new Function(SOURCE.slice(open + 8, close));
}

beforeAll(() => {
  // jsdom does not lay out: every element counts as shown.
  Object.defineProperty(HTMLElement.prototype, 'offsetWidth', { configurable: true, get: () => 10 });
  Object.defineProperty(HTMLElement.prototype, 'offsetHeight', { configurable: true, get: () => 10 });
  if (!window.CSS) window.CSS = {};
  if (!window.CSS.escape) window.CSS.escape = (s) => String(s);
  global.CSS = window.CSS;
  Element.prototype.scrollIntoView = () => {};
});

describe('the page information the browser tool reads', () => {
  it('leaves out what is typed in password and other secret fields', () => {
    document.body.innerHTML = `
      <input id="user" type="text">
      <input id="pass" type="password">
      <input id="otp" type="text" autocomplete="one-time-code">
      <input id="card" type="text" autocomplete="billing cc-number">`;
    document.getElementById('user').value = 'alice';
    document.getElementById('pass').value = 's3cret-pass';
    document.getElementById('otp').value = '123456';
    document.getElementById('card').value = '4111111111111111';
    const items = scriptOf('_get_page_info')();
    const text = JSON.stringify(items);
    expect(text).toContain('alice');
    expect(text).not.toContain('s3cret-pass');
    expect(text).not.toContain('123456');
    expect(text).not.toContain('4111111111111111');
  });
});

describe('what the browser tool is told after typing', () => {
  function typeScript() {
    const start = SOURCE.indexOf('el.value = arguments[1];');
    const open = SOURCE.lastIndexOf('js = """', start);
    const close = SOURCE.indexOf('"""', start);
    return new Function(SOURCE.slice(open + 8, close));
  }

  it('does not give back a password field\'s value', () => {
    document.body.innerHTML = '<input id="pass" type="password"><input id="name" type="text">';
    const typed = typeScript();
    expect(typed('#pass', 's3cret-pass').value).toBe('');
    expect(typed('#name', 'Alice').value).toBe('Alice');
  });
});
