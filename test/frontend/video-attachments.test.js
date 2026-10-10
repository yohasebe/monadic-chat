/**
 * @jest-environment jsdom
 */

/**
 * Videos attached in the chat (select_image.js, loaded as it ships): they go
 * to the server as attachments of this chat, are shown until sent, and are
 * named in the message by attachment_id. Only apps that import the
 * video_analysis tools take them.
 */

const SOURCE = '../../docker/services/ruby/public/js/monadic/select_image.js';

function load({ toolGroups }) {
  document.body.innerHTML = `
    <div id="image-used"></div>
    <select id="apps"><option value="VideoDescriberApp" selected>VideoDescriberApp</option></select>
    <select id="model"><option value="gpt-6.1-sol" selected>gpt</option></select>
    <button id="image-file"></button>
    <div id="imageModal"><h5 id="imageModalLabel"></h5>
      <input type="file" id="imageFile" accept=".jpg"><label for="imageFile">File to import</label>
      <div id="select_image_error"></div><button id="uploadImage"></button></div>`;
  global.$id = (id) => document.getElementById(id);
  global.$show = () => {};
  global.$hide = () => {};
  global.setAlert = jest.fn();
  global.getTranslation = (_key, fallback) => fallback;
  window.escapeHtml = (s) => String(s).replace(/</g, '&lt;');
  global.bootstrap = { Modal: { getOrCreateInstance: () => ({ show() {}, hide() {} }) } };
  global.apps = { VideoDescriberApp: { imported_tool_groups: JSON.stringify(toolGroups) } };
  // The tab id comes from ws-tab-id.js, as the WebSocket's does.
  window.getMonadicTabId = () => 'tab 1';
  window.monadicFetch = { postJson: jest.fn() };
  jest.isolateModules(() => { require(SOURCE); });
}

describe('video attachments', () => {
  it('are offered only by apps that import the video tools', () => {
    load({ toolGroups: [{ name: 'video_analysis', available: true }] });
    expect(window.appTakesVideoAttachments('VideoDescriberApp')).toBe(true);
    load({ toolGroups: [{ name: 'image_analysis', available: true }] });
    expect(window.appTakesVideoAttachments('VideoDescriberApp')).toBe(false);
    load({ toolGroups: [{ name: 'video_analysis', available: false }] });
    expect(window.appTakesVideoAttachments('VideoDescriberApp')).toBe(false);
    expect(window.appTakesVideoAttachments('NoSuchApp')).toBe(false);
  });

  it('tell video files by their extension', () => {
    load({ toolGroups: [] });
    expect(window.isVideoFile({ name: 'clip.MOV' })).toBe(true);
    expect(window.isVideoFile({ name: 'photo.png' })).toBe(false);
  });

  it('upload to this tab’s chat as a video, then show until sent', async () => {
    load({ toolGroups: [{ name: 'video_analysis', available: true }] });
    window.monadicFetch.postJson.mockResolvedValue({ attachment_id: 'a_123', name: 'clip.mp4', size: 3 * 1024 * 1024 });
    await window.uploadVideoAttachment(new File(['x'], 'clip.mp4', { type: 'video/mp4' }));

    const [url, form] = window.monadicFetch.postJson.mock.calls[0];
    expect(url).toBe('/attachments?tab_id=tab%201');
    expect(form.get('purpose')).toBe('video');
    expect(form.get('file').name).toBe('clip.mp4');
    expect(window.hasVideoAttachments()).toBe(true);
    expect(document.getElementById('image-used').textContent).toContain('clip.mp4 (3.0 MB)');
  });

  it('are named in the message, and stay listed until cleared', async () => {
    load({ toolGroups: [{ name: 'video_analysis', available: true }] });
    window.monadicFetch.postJson.mockResolvedValue({ attachment_id: 'a_123', name: 'clip.mp4', size: 1 });
    await window.uploadVideoAttachment(new File(['x'], 'clip.mp4'));

    expect(window.videoAttachmentLines()).toBe('Attached video: clip.mp4 (attachment_id: a_123)');
    // Building the message does not clear the list: a failed send keeps it.
    expect(window.hasVideoAttachments()).toBe(true);
    window.clearVideoAttachments();
    expect(window.videoAttachmentLines()).toBe('');
    expect(document.getElementById('image-used').textContent).not.toContain('clip.mp4');
  });

  it('drop an upload that finishes after the list was cleared (Reset or app switch meanwhile)', async () => {
    load({ toolGroups: [{ name: 'video_analysis', available: true }] });
    let finish;
    window.monadicFetch.postJson.mockReturnValue(new Promise((resolve) => { finish = resolve; }));
    const pending = window.uploadVideoAttachment(new File(['x'], 'old.mp4'));
    window.clearAllImages();
    finish({ attachment_id: 'a_old', name: 'old.mp4', size: 1 });
    await expect(pending).resolves.toBeNull();
    expect(window.hasVideoAttachments()).toBe(false);
  });

  it('can be removed before sending, and are cleared with the images', async () => {
    load({ toolGroups: [{ name: 'video_analysis', available: true }] });
    window.monadicFetch.postJson.mockResolvedValue({ attachment_id: 'a_1', name: 'a.mp4', size: 1 });
    await window.uploadVideoAttachment(new File(['x'], 'a.mp4'));
    document.querySelector('.remove-video').click();
    expect(window.hasVideoAttachments()).toBe(false);

    await window.uploadVideoAttachment(new File(['x'], 'b.mp4'));
    window.clearAllImages();
    expect(window.hasVideoAttachments()).toBe(false);
  });

  it('leave nothing behind when the server refuses the file', async () => {
    load({ toolGroups: [{ name: 'video_analysis', available: true }] });
    window.monadicFetch.postJson.mockRejectedValue(new Error('The file is larger than the 2000 MB limit.'));
    await expect(window.uploadVideoAttachment(new File(['x'], 'big.mp4'))).rejects.toThrow('2000 MB');
    expect(window.hasVideoAttachments()).toBe(false);
  });
});

// The tab id is read through ws-tab-id.js, which the WebSocket uses. A
// window.tabId was read in two places and never set anywhere, so uploads
// carried no tab and the server could not tell which chat they were for.
describe('tab id', () => {
  it('is not read from window.tabId anywhere in the web UI', () => {
    const fs = require('fs');
    const path = require('path');
    const root = path.resolve(__dirname, '../../docker/services/ruby/public/js');
    const files = [];
    const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).forEach((e) => {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) walk(full);
      else if (e.name.endsWith('.js') && !e.name.includes('.min.')) files.push(full);
    });
    walk(root);
    expect(files.length).toBeGreaterThan(50);
    const offenders = files.filter((f) => /window\.tabId\b/.test(fs.readFileSync(f, 'utf8')));
    expect(offenders).toEqual([]);
  });
});

// Reset asks for confirmation; cancelling it must leave what is attached.
// The clearing lives in doResetActions, which runs only once confirmed.
describe('reset', () => {
  it('clears attachments only after the reset is confirmed', () => {
    const fs = require('fs');
    const path = require('path');
    const src = fs.readFileSync(path.resolve(__dirname, '../../docker/services/ruby/public/js/monadic/utilities.js'), 'utf8');
    const body = (name) => {
      const start = src.indexOf('function ' + name + '(');
      const next = src.indexOf('\nfunction ', start + 1);
      return src.slice(start, next === -1 ? undefined : next);
    };
    expect(body('resetEvent')).not.toMatch(/clearVideoAttachments|images = \[\]/);
    expect(body('doResetActions')).toMatch(/clearVideoAttachments\(\)/);
    expect(body('doResetActions')).toMatch(/images = \[\]/);
  });
});

// A message that cannot be sent (the connection is down) leaves what was
// typed and attached in place: nothing is cleared before the send succeeded.
describe('sending while disconnected', () => {
  it('clears the input box only after the message was sent, for chat and sample messages', () => {
    const fs = require('fs');
    const path = require('path');
    const src = fs.readFileSync(path.resolve(__dirname, '../../docker/services/ruby/public/js/monadic.js'), 'utf8');
    const sends = [...src.matchAll(/const (sendResult|sampleResult) = window\.safeWsSend\(/g)];
    expect(sends.length).toBe(2);
    sends.forEach((m) => {
      const after = src.slice(m.index);
      const check = after.search(/restoreAfterUnsentMessage\(\);\s*return;/);
      const clear = after.search(/el\.value = ""/);
      expect(check).toBeGreaterThan(-1);
      expect(check).toBeLessThan(clear);
    });
  });

  it('keeps the role of a sample message that could not be sent', () => {
    const fs = require('fs');
    const path = require('path');
    const src = fs.readFileSync(path.resolve(__dirname, '../../docker/services/ruby/public/js/monadic.js'), 'utf8');
    const sample = src.indexOf('const sampleResult = window.safeWsSend(');
    const after = src.slice(sample);
    const check = after.search(/restoreAfterUnsentMessage\(\);\s*return;/);
    const roleBack = after.search(/select-role"\); if \(el\) \{ el\.value = "user"/);
    expect(check).toBeGreaterThan(-1);
    expect(check).toBeLessThan(roleBack);
    // No unconditional switch back to "user" after the send callbacks.
    expect(src).not.toMatch(/\{ const el = \$id\("select-role"\); if \(el\) el\.value = "user"; \}/);
  });
});

// Cancel gives up an AI User suggestion when pressed: its notices may already
// be on the way and must not fill the input box afterwards.
describe('cancel', () => {
  it('gives up the AI User request when pressed', () => {
    const fs = require('fs');
    const path = require('path');
    const src = fs.readFileSync(path.resolve(__dirname, '../../docker/services/ruby/public/js/monadic.js'), 'utf8');
    const start = src.indexOf('$on($id("cancel_query"), "click"');
    expect(start).toBeGreaterThan(-1);
    expect(src.slice(start, start + 600)).toMatch(/abandonAIUser\(\)/);
  });
});
