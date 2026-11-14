// The right-click items that copy a link's or an image's address put it on
// the clipboard as plain text.
const { copyAddressItems } = require('../../app/context_menu_copy');

describe('copy address items', () => {
  let clipboard;
  beforeEach(() => { clipboard = { writeText: jest.fn(), write: jest.fn() }; });

  test('a link is copied as its address in plain text', () => {
    const items = copyAddressItems({ linkURL: 'http://127.0.0.1:8889/lab/tree/a.ipynb', linkText: 'a.ipynb', mediaType: 'none' }, clipboard);
    items.find(item => item.id === 'copyLink').click();
    expect(clipboard.writeText).toHaveBeenCalledWith('http://127.0.0.1:8889/lab/tree/a.ipynb');
    expect(clipboard.write).not.toHaveBeenCalled();
  });

  test('an image is copied as its address in plain text', () => {
    const items = copyAddressItems({ linkURL: '', srcURL: 'http://localhost:4567/a.png', mediaType: 'image' }, clipboard);
    expect(items.map(item => item.id)).toEqual(['copyImageAddress', undefined]);
    items[0].click();
    expect(clipboard.writeText).toHaveBeenCalledWith('http://localhost:4567/a.png');
  });

  test('an image inside a link gives only the image address', () => {
    const items = copyAddressItems({ linkURL: 'http://localhost:4567/', srcURL: 'http://localhost:4567/a.png', mediaType: 'image' }, clipboard);
    expect(items.map(item => item.id)).toEqual(['copyImageAddress', undefined]);
  });

  test('there is nothing to copy where there is no address', () => {
    expect(copyAddressItems({ linkURL: '', srcURL: '', mediaType: 'none' }, clipboard)).toEqual([]);
  });
});
