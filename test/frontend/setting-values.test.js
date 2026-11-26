const fs = require('fs');
const path = require('path');
const { onUnlessFalse } = require('../../app/setting_values');

describe('a setting that is on unless turned off', () => {
  it('is on when unset or anything but "false", and off for "false" in any case or spacing', () => {
    expect([undefined, null, '', 'true', 'yes', 'TRUE'].map(onUnlessFalse)).toEqual([true, true, true, true, true, true]);
    expect(['false', 'False', ' FALSE ', 'false\n'].map(onUnlessFalse)).toEqual([false, false, false, false]);
  });

  it('is shown and saved by the settings window through the same reading', () => {
    const html = fs.readFileSync(path.join(__dirname, '../../app/settings.html'), 'utf8');
    expect(html).toContain('<script src="./setting_values.js"></script>');
    for (const [key, id] of [['LIBRARY_IN_CHATS', 'library-in-chats'], ['BACKGROUND_REPLY_NOTIFICATIONS', 'background-reply-notifications']]) {
      expect(html).toContain(`document.getElementById('${id}').checked = window.settingValues.onUnlessFalse(data.${key});`);
      expect(html).toMatch(new RegExp(`${key}: document\\.getElementById\\('${id}'\\)\\.checked`));
    }
  });
});
