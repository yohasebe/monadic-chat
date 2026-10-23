/**
 * @jest-environment jsdom
 */
// With Bootstrap's own modal, Enter goes to the dialog while it fades in,
// while it is shown and while it fades out; once it is hidden, Easy Submit
// sends the draft again.
const path = require('path');

const ROOT = path.join(__dirname, '../..');
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

describe('Easy Submit and a fading Bootstrap modal', () => {
  let bootstrap; let sent;

  beforeAll(() => {
    document.body.innerHTML = `
      <input type="checkbox" id="check-easy-submit" checked>
      <textarea id="message">a draft</textarea>
      <button id="send"></button>
      <div class="modal fade" id="dialog" tabindex="-1" style="transition-duration: 0.1s">
        <div class="modal-dialog"><div class="modal-content" style="transition-duration: 0.1s">
          <div class="modal-footer"><button type="button" id="cancel" class="btn" data-bs-dismiss="modal">Cancel</button></div>
        </div></div>
      </div>`;
    global.$id = (id) => document.getElementById(id);
    sent = jest.fn();
    document.getElementById('send').addEventListener('click', sent);
    bootstrap = require(path.join(ROOT, 'docker/services/ruby/public/vendor/js/bootstrap.bundle.min.js'));
    require(path.join(ROOT, 'docker/services/ruby/public/js/monadic/ws-input-handler.js'));
  });

  const enterOn = (el) => el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));

  test('Enter reaches the chat only after the dialog is hidden', async () => {
    const dialog = document.getElementById('dialog');
    const cancel = document.getElementById('cancel');
    const modal = new bootstrap.Modal(dialog, { backdrop: false });

    modal.show();
    enterOn(cancel); // fading in
    await wait(300);
    expect(dialog.classList.contains('show')).toBe(true);
    cancel.focus();
    enterOn(cancel); // shown

    cancel.click(); // starts hiding: Bootstrap removes .show first
    expect(dialog.classList.contains('show')).toBe(false);
    enterOn(cancel); // fading out
    expect(sent).not.toHaveBeenCalled();

    await wait(300);
    expect(document.body.classList.contains('modal-open')).toBe(false);
    enterOn(document.body); // hidden
    expect(sent).toHaveBeenCalledTimes(1);
  });
});
