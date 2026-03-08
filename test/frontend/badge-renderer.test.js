/**
 * Tests for badge-renderer.js
 *
 * Badge rendering for app tool groups and capabilities.
 */

// Setup globals
global.apps = {
  'TestApp': {
    description: 'Test application',
    all_badges: {
      tools: [
        { id: 'web', label: 'Web Search', description: '3 tools', icon: 'fa-search', visibility: 'always', type: 'tools' },
        { id: 'code', label: 'Code Runner', description: '2 tools', icon: 'fa-code', visibility: 'conditional', type: 'tools' }
      ],
      capabilities: [
        { id: 'mathjax', label: 'MathJax', description: 'Math rendering', icon: 'fa-calculator', type: 'capabilities' }
      ]
    }
  },
  'EmptyApp': {
    description: 'Empty app'
  },
  'StringBadgeApp': {
    description: 'String badges',
    all_badges: JSON.stringify({
      tools: [{ id: 'tool1', label: 'Tool 1', description: 'A tool', icon: 'fa-wrench', visibility: 'always', type: 'tools' }],
      capabilities: []
    })
  },
  'ImportedGroupApp': {
    description: 'Imported groups',
    imported_tool_groups: [
      { name: 'FileOps', tool_count: 5, visibility: 'always' }
    ]
  }
};

let lastDescription = '';
global.setBaseAppDescription = function(html) { lastDescription = html; };
global.$ = function() { return { length: 0 }; };

const {
  updateAppBadges,
  filterToolBadges,
  filterCapabilityBadges,
  renderBadge,
  getBadgeColorClass,
  getUserControlCheckbox,
  isToolGroupAvailable
} = require('../../docker/services/ruby/public/js/monadic/badge-renderer');

describe('badge-renderer', () => {
  beforeEach(() => {
    lastDescription = '';
  });

  describe('updateAppBadges', () => {
    it('renders badges for app with all_badges object', () => {
      updateAppBadges('TestApp');
      expect(lastDescription).toContain('Web Search');
      expect(lastDescription).toContain('Code Runner');
      expect(lastDescription).toContain('MathJax');
      expect(lastDescription).toContain('tool-groups-display');
    });

    it('renders description only for app with no badges', () => {
      updateAppBadges('EmptyApp');
      expect(lastDescription).toBe('Empty app');
    });

    it('handles string badge data (JSON parse)', () => {
      updateAppBadges('StringBadgeApp');
      expect(lastDescription).toContain('Tool 1');
    });

    it('falls back to imported_tool_groups', () => {
      updateAppBadges('ImportedGroupApp');
      expect(lastDescription).toContain('FileOps');
    });

    it('handles null/undefined app gracefully', () => {
      expect(() => updateAppBadges(null)).not.toThrow();
      expect(() => updateAppBadges('NonexistentApp')).not.toThrow();
    });
  });

  describe('filterToolBadges', () => {
    it('passes through always-visible badges', () => {
      const badges = [{ visibility: 'always', id: 'test' }];
      expect(filterToolBadges(badges)).toHaveLength(1);
    });

    it('includes conditional badges when group is available', () => {
      const badges = [{ visibility: 'conditional', id: 'test' }];
      expect(filterToolBadges(badges)).toHaveLength(1);
    });
  });

  describe('filterCapabilityBadges', () => {
    it('returns all badges unchanged', () => {
      const badges = [{ id: 'a' }, { id: 'b' }];
      expect(filterCapabilityBadges(badges)).toEqual(badges);
    });
  });

  describe('renderBadge', () => {
    it('renders badge with icon and label', () => {
      const html = renderBadge({ icon: 'fa-search', label: 'Search', description: 'Web search', type: 'tools' });
      expect(html).toContain('fa-search');
      expect(html).toContain('Search');
      expect(html).toContain('badge-tools');
    });

    it('includes title attribute with description', () => {
      const html = renderBadge({ icon: 'fa-code', label: 'Code', description: 'Code tools', type: 'tools' });
      expect(html).toContain('title="Code tools"');
    });
  });

  describe('getBadgeColorClass', () => {
    it('returns badge-tools for tool type', () => {
      expect(getBadgeColorClass({ type: 'tools' })).toBe('badge-tools');
    });

    it('returns badge-capabilities for capability type', () => {
      expect(getBadgeColorClass({ type: 'capabilities' })).toBe('badge-capabilities');
    });

    it('returns badge-default for unknown type', () => {
      expect(getBadgeColorClass({ type: 'other' })).toBe('badge-default');
    });
  });

  describe('isToolGroupAvailable', () => {
    it('returns true (stub)', () => {
      expect(isToolGroupAvailable('any')).toBe(true);
    });
  });

  describe('exports', () => {
    it('exports updateAppBadges to window', () => {
      expect(window.updateAppBadges).toBe(updateAppBadges);
    });
  });
});
