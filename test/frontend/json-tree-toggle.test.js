/**
 * Tests for json-tree-toggle.js
 *
 * JSON tree expand/collapse with CSS animations.
 */

const { toggleItem, updateItemStates, onNewElementAdded, applyCollapseStates } = require('../../docker/services/ruby/public/js/monadic/json-tree-toggle');

describe('json-tree-toggle', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
  });

  function createJsonItem(key, depth, collapsed) {
    const item = document.createElement('div');
    item.className = 'json-item';
    item.dataset.key = key;
    item.dataset.depth = String(depth);

    const header = document.createElement('div');
    header.className = 'json-header';

    const chevron = document.createElement('i');
    chevron.className = collapsed ? 'fa-chevron-right' : 'fa-chevron-down';
    header.appendChild(chevron);

    const toggleText = document.createElement('span');
    toggleText.className = 'toggle-text';
    toggleText.textContent = collapsed ? 'Show details' : 'Hide details';
    header.appendChild(toggleText);

    const content = document.createElement('div');
    content.className = 'json-content';
    content.style.display = collapsed ? 'none' : 'block';
    content.textContent = 'Content here';

    item.appendChild(header);
    item.appendChild(content);
    return { item, header, content, chevron, toggleText };
  }

  describe('toggleItem', () => {
    it('opens a collapsed item', () => {
      const { item, header, content, chevron } = createJsonItem('test', 1, true);
      document.body.appendChild(item);

      toggleItem(header);

      expect(content.style.display).toBe('block');
      expect(chevron.classList.contains('fa-chevron-down')).toBe(true);
    });

    it('closes an open item', () => {
      const { item, header, content, chevron } = createJsonItem('test', 1, false);
      document.body.appendChild(item);

      toggleItem(header);

      expect(content.style.maxHeight).toBe('0');
      expect(content.style.opacity).toBe('0');
      expect(chevron.classList.contains('fa-chevron-right')).toBe(true);
    });

    it('updates toggle text on open', () => {
      const { item, header, toggleText } = createJsonItem('test', 1, true);
      document.body.appendChild(item);

      toggleItem(header);

      expect(toggleText.textContent).toBe('Hide details');
    });

    it('updates toggle text on close', () => {
      const { item, header, toggleText } = createJsonItem('test', 1, false);
      document.body.appendChild(item);

      toggleItem(header);

      expect(toggleText.textContent).toBe('Show details');
    });

    it('handles missing content element gracefully', () => {
      const header = document.createElement('div');
      const chevron = document.createElement('i');
      chevron.className = 'fa-chevron-down';
      header.appendChild(chevron);
      // No sibling content element

      expect(() => toggleItem(header)).not.toThrow();
    });
  });

  describe('updateItemStates', () => {
    it('processes json-items in the DOM', () => {
      const { item } = createJsonItem('key1', 1, false);
      document.body.appendChild(item);

      // Should not throw
      expect(() => updateItemStates()).not.toThrow();
    });

    it('handles empty DOM', () => {
      expect(() => updateItemStates()).not.toThrow();
    });
  });

  describe('onNewElementAdded', () => {
    it('calls updateItemStates', () => {
      // onNewElementAdded is a thin wrapper around updateItemStates
      expect(() => onNewElementAdded()).not.toThrow();
    });
  });

  describe('applyCollapseStates', () => {
    it('calls updateItemStates', () => {
      expect(() => applyCollapseStates()).not.toThrow();
    });
  });

  describe('exports', () => {
    it('exports all functions to window', () => {
      expect(window.toggleItem).toBe(toggleItem);
      expect(window.updateItemStates).toBe(updateItemStates);
      expect(window.onNewElementAdded).toBe(onNewElementAdded);
      expect(window.applyCollapseStates).toBe(applyCollapseStates);
    });

    it('exports all functions via module.exports', () => {
      expect(typeof toggleItem).toBe('function');
      expect(typeof updateItemStates).toBe('function');
      expect(typeof onNewElementAdded).toBe('function');
      expect(typeof applyCollapseStates).toBe('function');
    });
  });
});
