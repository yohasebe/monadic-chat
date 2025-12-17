/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

// Helper to load ContextPanel file
function loadContextPanel() {
  const filePath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/context-panel.js');
  const code = fs.readFileSync(filePath, 'utf8');

  // Execute the code in the current context
  eval(code);
}

describe('ContextPanel Tests', () => {
  beforeEach(() => {
    // Clear any existing ContextPanel
    delete window.ContextPanel;

    // Set up DOM elements that context-panel.js expects
    document.body.innerHTML = `
      <div id="context-panel" style="display: none;">
        <div id="context-sections"></div>
        <button id="context-toggle-all"></button>
        <button id="context-save" style="display: block;"></button>
        <button id="context-cancel" style="display: block;"></button>
        <div id="context-legend" style="display: none;">
          <span id="context-turn-badge">0</span>
        </div>
      </div>
    `;

    // Load fresh ContextPanel
    loadContextPanel();

    // Manually initialize since DOMContentLoaded won't fire
    window.ContextPanel.init();
  });

  afterEach(() => {
    // Clean up DOM
    document.body.innerHTML = '';
  });

  describe('Initialization', () => {
    test('should initialize with default values', () => {
      expect(window.ContextPanel).toBeDefined();
      expect(window.ContextPanel.currentContext).toBeNull();
      expect(window.ContextPanel.currentSchema).toBeNull();
      expect(window.ContextPanel.isVisible).toBe(false);
      expect(window.ContextPanel.currentAppName).toBeNull();
    });

    test('should cache DOM elements', () => {
      expect(window.ContextPanel.panel).toBeDefined();
      expect(window.ContextPanel.sectionsContainer).toBeDefined();
    });

    test('should hide edit buttons on init', () => {
      const saveBtn = document.getElementById('context-save');
      const cancelBtn = document.getElementById('context-cancel');

      expect(saveBtn.style.display).toBe('none');
      expect(cancelBtn.style.display).toBe('none');
    });
  });

  describe('Default Schema', () => {
    test('should have three default fields', () => {
      expect(window.ContextPanel.defaultSchema.fields.length).toBe(3);
    });

    test('should include topics, people, and notes fields', () => {
      const fieldNames = window.ContextPanel.defaultSchema.fields.map(f => f.name);
      expect(fieldNames).toContain('topics');
      expect(fieldNames).toContain('people');
      expect(fieldNames).toContain('notes');
    });

    test('should provide icons and labels for default fields', () => {
      window.ContextPanel.defaultSchema.fields.forEach(field => {
        expect(field).toHaveProperty('icon');
        expect(field).toHaveProperty('label');
        expect(field).toHaveProperty('description');
      });
    });
  });

  describe('Show/Hide Panel', () => {
    test('should show panel and set visibility flag', () => {
      window.ContextPanel.show('TestApp');

      expect(window.ContextPanel.panel.style.display).toBe('block');
      expect(window.ContextPanel.isVisible).toBe(true);
      expect(window.ContextPanel.currentAppName).toBe('TestApp');
    });

    test('should hide panel and reset state', () => {
      window.ContextPanel.show('TestApp');
      window.ContextPanel.hide();

      expect(window.ContextPanel.panel.style.display).toBe('none');
      expect(window.ContextPanel.isVisible).toBe(false);
      expect(window.ContextPanel.currentContext).toBeNull();
    });

    test('should reset context when switching apps', () => {
      // Show first app with context
      window.ContextPanel.show('App1');
      window.ContextPanel.updateContext({
        topics: [{ text: 'AI', turn: 1 }],
        people: [],
        notes: []
      });

      // Switch to second app
      window.ContextPanel.show('App2');

      expect(window.ContextPanel.currentContext).toBeNull();
      expect(window.ContextPanel.currentAppName).toBe('App2');
    });

    test('should accept custom schema when showing', () => {
      const customSchema = {
        fields: [
          { name: 'vocabulary', icon: 'fa-book', label: 'Vocabulary', description: 'Words' }
        ]
      };

      window.ContextPanel.show('LanguageApp', customSchema);

      expect(window.ContextPanel.currentSchema).toEqual(customSchema);
    });
  });

  describe('Update Context', () => {
    beforeEach(() => {
      window.ContextPanel.show('TestApp');
    });

    test('should update current context', () => {
      const context = {
        topics: [{ text: 'AI', turn: 1 }],
        people: [{ text: 'John', turn: 1 }],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      expect(window.ContextPanel.currentContext).toEqual(context);
    });

    test('should update schema when provided', () => {
      const customSchema = {
        fields: [{ name: 'custom', icon: 'fa-star', label: 'Custom', description: 'Test' }]
      };

      window.ContextPanel.updateContext({}, customSchema);

      expect(window.ContextPanel.currentSchema).toEqual(customSchema);
    });

    test('should render when visible', () => {
      const context = {
        topics: [{ text: 'AI', turn: 1 }],
        people: [],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const sections = document.querySelector('.context-section');
      expect(sections).not.toBeNull();
    });
  });

  describe('Render Context', () => {
    beforeEach(() => {
      window.ContextPanel.show('TestApp');
    });

    test('should render sections for fields with content', () => {
      const context = {
        topics: [{ text: 'AI', turn: 1 }, { text: 'ML', turn: 2 }],
        people: [{ text: 'John', turn: 1 }],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const sections = document.querySelectorAll('.context-section');
      expect(sections.length).toBe(2); // topics and people, not notes (empty)
    });

    test('should display placeholder for empty context', () => {
      window.ContextPanel.updateContext({
        topics: [],
        people: [],
        notes: []
      });

      const placeholder = document.querySelector('.text-muted');
      expect(placeholder).not.toBeNull();
      expect(placeholder.textContent).toContain('Context will appear');
    });

    test('should group items by turn', () => {
      const context = {
        topics: [
          { text: 'AI', turn: 1 },
          { text: 'ML', turn: 1 },
          { text: 'Ruby', turn: 2 }
        ],
        people: [],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const turnGroups = document.querySelectorAll('.context-turn-group');
      expect(turnGroups.length).toBe(2); // Two turns
    });

    test('should show turn labels', () => {
      const context = {
        topics: [{ text: 'AI', turn: 1 }],
        people: [],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const turnLabel = document.querySelector('.context-turn-label');
      expect(turnLabel).not.toBeNull();
      expect(turnLabel.textContent).toBe('T1');
    });

    test('should show item count badge', () => {
      const context = {
        topics: [
          { text: 'AI', turn: 1 },
          { text: 'ML', turn: 2 }
        ],
        people: [],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const badge = document.querySelector('.context-badge');
      expect(badge).not.toBeNull();
      expect(badge.textContent).toBe('2');
    });
  });

  describe('Section Toggle', () => {
    beforeEach(() => {
      window.ContextPanel.show('TestApp');
      window.ContextPanel.updateContext({
        topics: [{ text: 'AI', turn: 1 }],
        people: [],
        notes: []
      });
    });

    test('should toggle section collapsed state', () => {
      const header = document.querySelector('.context-section-header');
      const section = document.querySelector('.context-section');

      expect(section.classList.contains('collapsed')).toBe(false);

      // Click to collapse
      header.click();
      expect(section.classList.contains('collapsed')).toBe(true);

      // Click to expand
      header.click();
      expect(section.classList.contains('collapsed')).toBe(false);
    });
  });

  describe('Toggle All Sections', () => {
    beforeEach(() => {
      window.ContextPanel.show('TestApp');
      window.ContextPanel.updateContext({
        topics: [{ text: 'AI', turn: 1 }],
        people: [{ text: 'John', turn: 1 }],
        notes: [{ text: 'Note', turn: 1 }]
      });
    });

    test('should collapse all sections when some are expanded', () => {
      window.ContextPanel.toggleAllSections();

      const sections = document.querySelectorAll('.context-section');
      sections.forEach(section => {
        expect(section.classList.contains('collapsed')).toBe(true);
      });
    });

    test('should expand all sections when all are collapsed', () => {
      // First collapse all
      window.ContextPanel.toggleAllSections();

      // Then expand all
      window.ContextPanel.toggleAllSections();

      const sections = document.querySelectorAll('.context-section');
      sections.forEach(section => {
        expect(section.classList.contains('collapsed')).toBe(false);
      });
    });
  });

  describe('Format Display Name', () => {
    test('should convert snake_case to Title Case', () => {
      expect(window.ContextPanel.formatDisplayName('target_lang')).toBe('Target Lang');
      expect(window.ContextPanel.formatDisplayName('grammar_points')).toBe('Grammar Points');
    });

    test('should capitalize single words', () => {
      expect(window.ContextPanel.formatDisplayName('topics')).toBe('Topics');
    });
  });

  describe('Get Icon For Key', () => {
    test('should return correct icon for known keys', () => {
      expect(window.ContextPanel.getIconForKey('topics')).toBe('fa-tags');
      expect(window.ContextPanel.getIconForKey('people')).toBe('fa-users');
      expect(window.ContextPanel.getIconForKey('notes')).toBe('fa-sticky-note');
      expect(window.ContextPanel.getIconForKey('code')).toBe('fa-code');
    });

    test('should return fallback icon for unknown keys', () => {
      expect(window.ContextPanel.getIconForKey('unknown_field')).toBe('fa-circle');
    });
  });

  describe('Escape HTML', () => {
    test('should escape HTML entities', () => {
      expect(window.ContextPanel.escapeHtml('<script>')).toBe('&lt;script&gt;');
      expect(window.ContextPanel.escapeHtml('&')).toBe('&amp;');
      // Note: Double quotes are not escaped in text content (only needed in attributes)
      // The escapeHtml function uses textContent/innerHTML which is correct for text nodes
      expect(window.ContextPanel.escapeHtml('"')).toBe('"');
    });

    test('should handle normal text', () => {
      expect(window.ContextPanel.escapeHtml('Hello World')).toBe('Hello World');
    });
  });

  describe('Get Effective Schema', () => {
    test('should return current schema when set', () => {
      const customSchema = {
        fields: [{ name: 'custom', icon: 'fa-star', label: 'Custom', description: 'Test' }]
      };

      window.ContextPanel.currentSchema = customSchema;

      expect(window.ContextPanel.getEffectiveSchema()).toEqual(customSchema);
    });

    test('should return default schema when no custom schema', () => {
      window.ContextPanel.currentSchema = null;

      expect(window.ContextPanel.getEffectiveSchema()).toEqual(window.ContextPanel.defaultSchema);
    });
  });

  describe('Legend Visibility', () => {
    test('should show legend with turn count', () => {
      window.ContextPanel.updateLegendVisibility(true, 3);

      const legend = document.getElementById('context-legend');
      const badge = document.getElementById('context-turn-badge');

      expect(legend.style.display).toBe('flex');
      expect(badge.textContent).toBe('3');
    });

    test('should hide legend', () => {
      window.ContextPanel.updateLegendVisibility(false);

      const legend = document.getElementById('context-legend');

      expect(legend.style.display).toBe('none');
    });
  });

  describe('Group Items By Turn', () => {
    test('should group items correctly', () => {
      const items = [
        { text: 'AI', turn: 1 },
        { text: 'ML', turn: 1 },
        { text: 'Ruby', turn: 2 }
      ];

      const grouped = window.ContextPanel.groupItemsByTurn(items);

      expect(Object.keys(grouped).length).toBe(2);
      expect(grouped[1].length).toBe(2);
      expect(grouped[2].length).toBe(1);
    });

    test('should handle string items (legacy format)', () => {
      const items = ['AI', 'ML'];

      const grouped = window.ContextPanel.groupItemsByTurn(items);

      expect(grouped[1].length).toBe(2);
    });
  });

  describe('Count Unique Turns', () => {
    test('should count unique turns', () => {
      const items = [
        { text: 'AI', turn: 1 },
        { text: 'ML', turn: 1 },
        { text: 'Ruby', turn: 2 },
        { text: 'Python', turn: 3 }
      ];

      const count = window.ContextPanel.countUniqueTurns(items);

      expect(count).toBe(3);
    });

    test('should handle items without turn info', () => {
      const items = ['AI', 'ML'];

      const count = window.ContextPanel.countUniqueTurns(items);

      expect(count).toBe(1); // All default to turn 1
    });
  });

  describe('Reset Context', () => {
    test('should clear all context state', () => {
      window.ContextPanel.show('TestApp');
      window.ContextPanel.updateContext({
        topics: [{ text: 'AI', turn: 1 }],
        people: [],
        notes: []
      });

      window.ContextPanel.resetContext();

      expect(window.ContextPanel.currentContext).toBeNull();
      expect(window.ContextPanel.currentSchema).toBeNull();
      expect(window.ContextPanel.currentAppName).toBeNull();
    });
  });

  describe('Scroll To Turn', () => {
    beforeEach(() => {
      // Set up discourse with message cards
      document.body.innerHTML += `
        <div id="discourse">
          <div class="card" data-turn="1">
            <div class="role-user">User message 1</div>
          </div>
          <div class="card" data-turn="1">
            <div class="role-assistant">Assistant response 1</div>
          </div>
          <div class="card" data-turn="2">
            <div class="role-user">User message 2</div>
          </div>
          <div class="card" data-turn="2">
            <div class="role-assistant">Assistant response 2</div>
          </div>
          <div id="temp-card" class="card" data-turn="3">
            <div class="role-assistant">Temp card</div>
          </div>
        </div>
      `;
      // Re-initialize panel with updated DOM
      window.ContextPanel.init();
    });

    test('should scroll to assistant card for given turn', () => {
      const scrollIntoViewMock = jest.fn();
      const assistantCard = document.querySelector('#discourse .card[data-turn="2"] .role-assistant').closest('.card');
      assistantCard.scrollIntoView = scrollIntoViewMock;

      window.ContextPanel.scrollToTurn(2);

      expect(scrollIntoViewMock).toHaveBeenCalledWith({ behavior: 'smooth', block: 'start' });
    });

    test('should fall back to user card if assistant card not found', () => {
      // Remove assistant card for turn 2
      const assistantDiv = document.querySelector('#discourse .card[data-turn="2"] .role-assistant');
      if (assistantDiv) {
        assistantDiv.closest('.card').remove();
      }

      const scrollIntoViewMock = jest.fn();
      const userCard = document.querySelector('#discourse .card[data-turn="2"] .role-user')?.closest('.card');
      if (userCard) {
        userCard.scrollIntoView = scrollIntoViewMock;
        window.ContextPanel.scrollToTurn(2);
        expect(scrollIntoViewMock).toHaveBeenCalled();
      }
    });

    test('should not scroll for invalid turn number', () => {
      const consoleWarnSpy = jest.spyOn(console, 'warn').mockImplementation();

      window.ContextPanel.scrollToTurn(0);

      expect(consoleWarnSpy).toHaveBeenCalledWith('[ContextPanel] Invalid turn number: 0');
      consoleWarnSpy.mockRestore();
    });

    test('should ignore temp-card when scrolling', () => {
      const scrollIntoViewMock = jest.fn();
      const tempCard = document.getElementById('temp-card');
      tempCard.scrollIntoView = scrollIntoViewMock;

      // Turn 3 only exists on temp-card, so should not scroll
      window.ContextPanel.scrollToTurn(3);

      expect(scrollIntoViewMock).not.toHaveBeenCalled();
    });

    test('should add and remove highlight class', () => {
      jest.useFakeTimers();

      const assistantCard = document.querySelector('#discourse .card[data-turn="1"] .role-assistant').closest('.card');
      assistantCard.scrollIntoView = jest.fn();

      window.ContextPanel.scrollToTurn(1);

      expect(assistantCard.classList.contains('context-highlight')).toBe(true);

      jest.advanceTimersByTime(2000);

      expect(assistantCard.classList.contains('context-highlight')).toBe(false);

      jest.useRealTimers();
    });
  });

  describe('Loading Indicator', () => {
    beforeEach(() => {
      // Add header with text span for loading indicator
      document.body.innerHTML = `
        <div id="context-panel" style="display: none;">
          <h5><span class="text">Context</span></h5>
          <div id="context-sections"></div>
          <button id="context-toggle-all"></button>
          <button id="context-save" style="display: block;"></button>
          <button id="context-cancel" style="display: block;"></button>
          <div id="context-legend" style="display: none;">
            <span id="context-turn-badge">0</span>
          </div>
        </div>
      `;
      window.ContextPanel.init();
    });

    test('should show loading indicator when panel is visible', () => {
      window.ContextPanel.show('TestApp');
      window.ContextPanel.showLoading();

      expect(window.ContextPanel.isLoading).toBe(true);
      const indicator = document.querySelector('.context-loading-indicator');
      expect(indicator).not.toBeNull();
    });

    test('should not show loading indicator when panel is not visible', () => {
      window.ContextPanel.showLoading();

      expect(window.ContextPanel.isLoading).toBe(false);
      const indicator = document.querySelector('.context-loading-indicator');
      expect(indicator).toBeNull();
    });

    test('should hide loading indicator', () => {
      window.ContextPanel.show('TestApp');
      window.ContextPanel.showLoading();
      window.ContextPanel.hideLoading();

      expect(window.ContextPanel.isLoading).toBe(false);
      const indicator = document.querySelector('.context-loading-indicator');
      expect(indicator).toBeNull();
    });

    test('should not add duplicate loading indicators', () => {
      window.ContextPanel.show('TestApp');
      window.ContextPanel.showLoading();
      window.ContextPanel.showLoading();

      const indicators = document.querySelectorAll('.context-loading-indicator');
      expect(indicators.length).toBe(1);
    });
  });

  describe('Edited Flag Handling', () => {
    beforeEach(() => {
      window.ContextPanel.show('TestApp');
    });

    test('should preserve edited flag when grouping items by turn', () => {
      const items = [
        { text: 'AI', turn: 1, edited: false },
        { text: 'ML', turn: 1, edited: true },
        { text: 'Ruby', turn: 2, edited: false }
      ];

      const grouped = window.ContextPanel.groupItemsByTurn(items);

      expect(grouped[1].some(item => item.edited === true)).toBe(true);
      expect(grouped[1].some(item => item.edited === false)).toBe(true);
      expect(grouped[2][0].edited).toBe(false);
    });

    test('should render edited badge for turns with edited items', () => {
      const context = {
        topics: [
          { text: 'AI', turn: 1, edited: true },
          { text: 'ML', turn: 2, edited: false }
        ],
        people: [],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const editedBadge = document.querySelector('.context-edited-badge');
      expect(editedBadge).not.toBeNull();
    });

    test('should add edited class to turn group with edited items', () => {
      const context = {
        topics: [
          { text: 'AI', turn: 1, edited: true }
        ],
        people: [],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const editedGroup = document.querySelector('.context-turn-group.edited');
      expect(editedGroup).not.toBeNull();
    });

    test('should not show edited badge for non-edited items', () => {
      const context = {
        topics: [
          { text: 'AI', turn: 1, edited: false },
          { text: 'ML', turn: 2, edited: false }
        ],
        people: [],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const editedBadges = document.querySelectorAll('.context-edited-badge');
      expect(editedBadges.length).toBe(0);
    });
  });

  describe('Turn Label Click Navigation', () => {
    beforeEach(() => {
      // Set up discourse with message cards
      document.body.innerHTML = `
        <div id="context-panel" style="display: none;">
          <div id="context-sections"></div>
          <button id="context-toggle-all"></button>
          <button id="context-save" style="display: none;"></button>
          <button id="context-cancel" style="display: none;"></button>
          <div id="context-legend" style="display: none;">
            <span id="context-turn-badge">0</span>
          </div>
        </div>
        <div id="discourse">
          <div class="card" data-turn="1">
            <div class="role-assistant">Response 1</div>
          </div>
        </div>
      `;
      window.ContextPanel.init();
      window.ContextPanel.show('TestApp');
    });

    test('should have clickable class on turn labels', () => {
      const context = {
        topics: [{ text: 'AI', turn: 1 }],
        people: [],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const turnLabel = document.querySelector('.context-turn-label');
      expect(turnLabel.classList.contains('clickable')).toBe(true);
    });

    test('should have data-turn attribute on turn labels', () => {
      const context = {
        topics: [{ text: 'AI', turn: 1 }],
        people: [],
        notes: []
      };

      window.ContextPanel.updateContext(context);

      const turnLabel = document.querySelector('.context-turn-label');
      expect(turnLabel.dataset.turn).toBe('1');
    });
  });
});
