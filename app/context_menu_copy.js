// The right-click items that copy an address: the link's, or the image's.
// The address goes to the clipboard as plain text, which every app can
// paste. (The menu library's own items write it as a bookmark with the
// text beside it, and on macOS that leaves the clipboard as it was.)

// The items for the place right-clicked (props, as the context-menu event
// gives them); none where there is no address to copy.
function copyAddressItems(props, clipboard) {
  const items = [];
  if (props.linkURL && props.mediaType === 'none') {
    items.push({ id: 'copyLink', label: 'Copy Lin&k', click: () => clipboard.writeText(props.linkURL) });
  }
  if (props.mediaType === 'image' && props.srcURL) {
    items.push({ id: 'copyImageAddress', label: 'Copy I&mage Address', click: () => clipboard.writeText(props.srcURL) });
  }
  if (items.length > 0) items.push({ type: 'separator' });
  return items;
}

module.exports = { copyAddressItems };
