/**
 * @jest-environment jsdom
 */

describe('WsAudioConstants Module', () => {
  let constants;

  beforeEach(() => {
    // Reset module registry
    jest.resetModules();

    // Provide navigator.userAgent for browser detection
    Object.defineProperty(window.navigator, 'userAgent', {
      value: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      configurable: true
    });
    Object.defineProperty(window.navigator, 'platform', {
      value: 'MacIntel',
      configurable: true
    });
    Object.defineProperty(window.navigator, 'maxTouchPoints', {
      value: 0,
      configurable: true
    });

    // Mock MediaSource
    window.MediaSource = jest.fn();
    window.AudioContext = jest.fn();

    constants = require('../../docker/services/ruby/public/js/monadic/ws-audio-constants');
  });

  afterEach(() => {
    delete window.WsAudioConstants;
    delete window.isIOS;
    delete window.MediaSource;
    delete window.AudioContext;
  });

  test('exports namespace to window.WsAudioConstants', () => {
    expect(window.WsAudioConstants).toBeDefined();
    expect(typeof window.WsAudioConstants).toBe('object');
  });

  test('detects Chrome browser correctly', () => {
    expect(constants.isChrome).toBe(true);
    expect(constants.isSafari).toBe(false);
    expect(constants.isFirefox).toBe(false);
  });

  test('detects non-iOS on desktop', () => {
    expect(constants.isIOS).toBe(false);
    expect(constants.isIPad).toBe(false);
    expect(constants.isMobileIOS).toBe(false);
  });

  test('detects MediaSource support', () => {
    expect(constants.hasMediaSourceSupport).toBe(true);
  });

  test('detects AudioContext support', () => {
    expect(constants.hasAudioContextSupport).toBe(true);
  });

  test('provides audio queue constants with defaults', () => {
    expect(constants.AUDIO_QUEUE_DELAY).toBe(20);
    expect(constants.AUDIO_ERROR_DELAY).toBe(50);
    expect(constants.MAX_AUDIO_QUEUE_SIZE).toBe(50);
  });

  test('provides sequence constants', () => {
    expect(constants.SEQUENCE_TIMEOUT_MS).toBe(3000);
    expect(constants.MAX_SEQUENCE_RETRIES).toBe(10);
  });

  test('provides reconnect constants', () => {
    expect(constants.maxReconnectAttempts).toBe(5);
    expect(constants.baseReconnectDelay).toBe(1000);
  });

  test('sets backward-compat window properties', () => {
    expect(window.isIOS).toBe(false);
    expect(window.isChrome).toBe(true);
  });

  test('module.exports matches window.WsAudioConstants', () => {
    expect(constants).toEqual(window.WsAudioConstants);
  });
});
