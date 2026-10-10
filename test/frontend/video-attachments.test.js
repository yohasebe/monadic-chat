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

  it('are named in the message once, then cleared', async () => {
    load({ toolGroups: [{ name: 'video_analysis', available: true }] });
    window.monadicFetch.postJson.mockResolvedValue({ attachment_id: 'a_123', name: 'clip.mp4', size: 1 });
    await window.uploadVideoAttachment(new File(['x'], 'clip.mp4'));

    expect(window.takeVideoAttachmentLines()).toBe('Attached video: clip.mp4 (attachment_id: a_123)');
    expect(window.hasVideoAttachments()).toBe(false);
    expect(window.takeVideoAttachmentLines()).toBe('');
    expect(document.getElementById('image-used').textContent).not.toContain('clip.mp4');
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
