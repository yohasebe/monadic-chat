/**
 * @jest-environment jsdom
 */
// An imported conversation is taken by the tab's own connection
// (IMPORT_APPLY); the import dialog reports what that connection did, not
// only that the request left the page. The function is read from
// monadic.js, which is too large to load whole here.
const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(
  path.join(__dirname, '../../docker/services/ruby/public/js/monadic.js'), 'utf8'
);
const start = source.indexOf('function applyImportOverConnection');
const end = source.indexOf('window.applyImportOverConnection = applyImportOverConnection;');
// eslint-disable-next-line no-new-func
const applyImportOverConnection = new Function(
  `${source.slice(start, end)}\nreturn applyImportOverConnection;`
)();

describe('applyImportOverConnection', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    window.onImportResult = null;
    window.safeWsSend = jest.fn(() => ({ sent: true }));
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('is found in monadic.js', () => {
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
  });

  it('sends the token and succeeds when the connection took the import', async () => {
    const result = applyImportOverConnection('t1');
    expect(window.safeWsSend).toHaveBeenCalledWith({ message: 'IMPORT_APPLY', token: 't1' });
    window.onImportResult({ type: 'import_result', token: 't1', success: true });
    await expect(result).resolves.toEqual({ success: true });
    expect(window.onImportResult).toBeNull();
  });

  it('reports the error the connection gives', async () => {
    const result = applyImportOverConnection('t1');
    window.onImportResult({ type: 'import_result', token: 't1', success: false, error: 'not found' });
    await expect(result).resolves.toEqual({ success: false, error: 'not found' });
  });

  it('ignores a result for another import', async () => {
    const result = applyImportOverConnection('t1');
    window.onImportResult({ type: 'import_result', token: 'other', success: true });
    jest.advanceTimersByTime(30000);
    const outcome = await result;
    expect(outcome.success).toBe(false);
  });

  it('fails at once when the message cannot be sent', async () => {
    window.safeWsSend = jest.fn(() => ({ sent: false }));
    const outcome = await applyImportOverConnection('t1');
    expect(outcome.success).toBe(false);
  });

  it('fails without a token', async () => {
    const outcome = await applyImportOverConnection(undefined);
    expect(outcome.success).toBe(false);
    expect(window.safeWsSend).not.toHaveBeenCalled();
  });
});
