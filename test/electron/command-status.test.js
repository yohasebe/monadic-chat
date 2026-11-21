// The console's status when a monadic.sh command ends.
const { statusAfterClose } = require('../../app/command_status');

describe('status after a command ends', () => {
  const ended = (command, code, serverStarted, statusAfterCommand = 'Running') =>
    statusAfterClose({ command, code, serverStarted, statusAfterCommand });

  test.each(['start', 'restart', 'build'])('%s that did not start the server ends Stopped, so Start can be pressed again', (command) => {
    expect(ended(command, 1, false)).toBe('Stopped');
    expect(ended(command, 0, false)).toBe('Stopped');
  });

  test.each(['start', 'restart', 'build'])('%s that started the server leaves the status to the check of the server', (command) => {
    expect(ended(command, 0, true)).toBeNull();
  });

  test('a build that failed after the server started ends Stopped', () => {
    expect(ended('build', 1, true)).toBe('Stopped');
  });

  test('other commands end in the status their caller named, whatever the exit code', () => {
    expect(ended('stop', 0, false, 'Stopped')).toBe('Stopped');
    expect(ended('build_ruby_container', 1, false, 'Stopped')).toBe('Stopped');
    expect(ended('stop-jupyter', 0, false, 'Running')).toBe('Running');
  });
});
