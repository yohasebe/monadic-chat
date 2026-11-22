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
      expect(config.color).toBe('var(--pal-green-text)');
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
    it('gives the palette token of a status type, which follows the theme', () => {
      expect(StatusConfig.getTextColor('success')).toBe('var(--pal-green-text)');
      expect(StatusConfig.getTextColor('danger')).toBe('var(--pal-red-text)');
    });

    it('gives the secondary text color for an unknown type', () => {
      expect(StatusConfig.getTextColor('invalid')).toBe('var(--text-secondary)');
    });
  });

  describe('exported constants', () => {
    it('exposes STATUS_CONFIG object', () => {
      expect(StatusConfig.STATUS_CONFIG).toBeDefined();
      expect(StatusConfig.STATUS_CONFIG.success).toBeDefined();
    });
  });
});
