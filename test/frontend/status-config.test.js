/**
 * @jest-environment jsdom
 */

describe('StatusConfig Module', () => {
  let StatusConfig;

  beforeEach(() => {
    // Execute the IIFE by loading the file
    require('../../docker/services/ruby/public/js/monadic/status-config.js');
    StatusConfig = window.StatusConfig;
  });

  afterEach(() => {
    jest.resetModules();
    delete window.StatusConfig;
  });

  describe('getStatusConfig', () => {
    it('returns config for valid status types', () => {
      const config = StatusConfig.getStatusConfig('success');
      expect(config).toBeDefined();
      expect(config.icon).toBe('fa-circle-check');
      expect(config.colorLight).toBeDefined();
      expect(config.colorDark).toBeDefined();
    });

    it('returns null for invalid status type', () => {
      expect(StatusConfig.getStatusConfig('nonexistent')).toBeNull();
    });

    it('returns null for undefined input', () => {
      expect(StatusConfig.getStatusConfig(undefined)).toBeNull();
    });
  });

  describe('getValidStatusTypes', () => {
    it('returns all five status types', () => {
      const types = StatusConfig.getValidStatusTypes();
      expect(types).toEqual(expect.arrayContaining(['success', 'warning', 'danger', 'info', 'secondary']));
      expect(types).toHaveLength(5);
    });
  });

  describe('isValidStatusType', () => {
    it('returns true for valid types', () => {
      expect(StatusConfig.isValidStatusType('success')).toBe(true);
      expect(StatusConfig.isValidStatusType('warning')).toBe(true);
      expect(StatusConfig.isValidStatusType('danger')).toBe(true);
      expect(StatusConfig.isValidStatusType('info')).toBe(true);
      expect(StatusConfig.isValidStatusType('secondary')).toBe(true);
    });

    it('returns false for invalid types', () => {
      expect(StatusConfig.isValidStatusType('unknown')).toBe(false);
      expect(StatusConfig.isValidStatusType('')).toBe(false);
    });
  });

  describe('getIconClass', () => {
    it('returns full icon class for valid type', () => {
      expect(StatusConfig.getIconClass('success')).toBe('fa-solid fa-circle-check');
      expect(StatusConfig.getIconClass('warning')).toBe('fa-solid fa-exclamation-triangle');
    });

    it('returns default icon for invalid type', () => {
      expect(StatusConfig.getIconClass('nonexistent')).toBe('fa-solid fa-circle-info');
    });
  });

  describe('getTextColor', () => {
    it('returns light mode color when isDark is false', () => {
      const color = StatusConfig.getTextColor('success', false);
      expect(color).toBe('#5cd65c');
    });

    it('returns dark mode color when isDark is true', () => {
      const color = StatusConfig.getTextColor('success', true);
      expect(color).toBe('#7fd89f');
    });

    it('returns default secondary color for invalid type', () => {
      expect(StatusConfig.getTextColor('invalid', false)).toBe('#757575');
      expect(StatusConfig.getTextColor('invalid', true)).toBe('#bdbdbd');
    });
  });

  describe('getBackgroundColor', () => {
    it('returns light background for light mode', () => {
      expect(StatusConfig.getBackgroundColor(false)).toBe('#707070');
    });

    it('returns dark background for dark mode', () => {
      expect(StatusConfig.getBackgroundColor(true)).toBe('#2a2a2a');
    });
  });

  describe('getBorderColor', () => {
    it('returns light border for light mode', () => {
      expect(StatusConfig.getBorderColor(false)).toBe('#808080');
    });

    it('returns dark border for dark mode', () => {
      expect(StatusConfig.getBorderColor(true)).toBe('#444444');
    });
  });

  describe('exported constants', () => {
    it('exposes STATUS_CONFIG object', () => {
      expect(StatusConfig.STATUS_CONFIG).toBeDefined();
      expect(StatusConfig.STATUS_CONFIG.success).toBeDefined();
    });

    it('exposes STATUS_BG object', () => {
      expect(StatusConfig.STATUS_BG).toBeDefined();
      expect(StatusConfig.STATUS_BG.light).toBeDefined();
      expect(StatusConfig.STATUS_BG.dark).toBeDefined();
    });

    it('exposes STATUS_BORDER object', () => {
      expect(StatusConfig.STATUS_BORDER).toBeDefined();
      expect(StatusConfig.STATUS_BORDER.light).toBeDefined();
      expect(StatusConfig.STATUS_BORDER.dark).toBeDefined();
    });
  });
});
