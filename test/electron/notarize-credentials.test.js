// The notarize hooks used to skip when credentials were missing and let the
// build succeed, producing a DMG that was not notarized. These cases pin the
// rule: a release build (MONADIC_RELEASE_BUILD=1, set by `rake build`) stops,
// other builds warn and skip, and no message carries a credential value.
const { isReleaseBuild, notarizeCredentials, credentialsOrSkip } = require('../../scripts/notarize_credentials');

const FAKE_PASSWORD = 'fake-app-specific-password-1234';

describe('notarization credentials', () => {
  test('a keychain profile wins, so no password passes through this process', () => {
    const creds = notarizeCredentials({
      NOTARY_PROFILE: 'shared-notary',
      APPLEID: 'dev@example.com', APPLEIDPASS: FAKE_PASSWORD, TEAMID: 'TEAM123456'
    });
    expect(creds).toEqual({ keychainProfile: 'shared-notary' });
    expect(notarizeCredentials({ MONADIC_RELEASE_BUILD: '1', NOTARY_PROFILE: 'p' })).toEqual({ keychainProfile: 'p' });
  });

  test('a release build does not accept the password path, which puts it in argv', () => {
    const env = { MONADIC_RELEASE_BUILD: '1', APPLEID: 'dev@example.com', APPLEIDPASS: FAKE_PASSWORD, TEAMID: 'TEAM123456' };
    expect(notarizeCredentials(env).missing).toMatch(/NOTARY_PROFILE/);
    expect(() => credentialsOrSkip('notarize', env, jest.fn())).toThrow(/release build stopped/);
  });

  test('other builds may still use the Apple ID, password and team', () => {
    expect(notarizeCredentials({ APPLEID: 'dev@example.com', APPLEIDPASS: FAKE_PASSWORD, TEAMID: 'TEAM123456' }))
      .toEqual({ appleId: 'dev@example.com', appleIdPassword: FAKE_PASSWORD, teamId: 'TEAM123456' });
  });

  test('never passes a 1Password reference on as the password', () => {
    const creds = notarizeCredentials({ APPLEID: 'dev@example.com', APPLEIDPASS: 'op://Vault/Item/password', TEAMID: 'T' });
    expect(creds.appleIdPassword).toBeUndefined();
    expect(creds.missing).toMatch(/1Password reference/);
    expect(creds.missing).not.toContain('Vault');
  });

  test('only MONADIC_RELEASE_BUILD=1 marks a release build', () => {
    expect(isReleaseBuild({ MONADIC_RELEASE_BUILD: '1' })).toBe(true);
    expect(isReleaseBuild({})).toBe(false);
    expect(isReleaseBuild({ MONADIC_RELEASE_BUILD: 'true' })).toBe(false);
  });

  test('a release build stops when credentials are missing', () => {
    expect(() => credentialsOrSkip('notarize', { MONADIC_RELEASE_BUILD: '1', APPLEIDPASS: FAKE_PASSWORD }, jest.fn()))
      .toThrow(/release build stopped/);
  });

  test('any other build warns and skips, as before', () => {
    const warn = jest.fn();
    expect(credentialsOrSkip('notarize-dmg', { APPLEIDPASS: FAKE_PASSWORD }, warn)).toBeNull();
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('skipping notarization'));
  });

  test('no message carries a credential value', () => {
    const warn = jest.fn();
    credentialsOrSkip('notarize', { APPLEIDPASS: FAKE_PASSWORD, TEAMID: 'TEAM123456' }, warn);
    let thrown = '';
    try {
      credentialsOrSkip('notarize', { MONADIC_RELEASE_BUILD: '1', APPLEIDPASS: FAKE_PASSWORD }, jest.fn());
    } catch (e) { thrown = e.message; }
    expect(JSON.stringify(warn.mock.calls) + thrown).not.toContain(FAKE_PASSWORD);
    expect(JSON.stringify(warn.mock.calls) + thrown).not.toContain('TEAM123456');
  });
});
