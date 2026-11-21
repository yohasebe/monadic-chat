// The status the console takes when a monadic.sh command ends. Commands that
// start the server (start, restart, build) say "[SERVER STARTED]" when the
// containers are up; the check of the server that follows that line sets
// Running, Ready or Stopped. So when such a command ends:
//   - with the line: nothing is set here (null)
//   - without it: the server did not start, and the status is Stopped, so
//     Start can be pressed again
// Every other command ends in the status its caller named.
const STARTS_SERVER = ['start', 'restart', 'build'];

function statusAfterClose({ command, code, serverStarted, statusAfterCommand }) {
  if (!STARTS_SERVER.includes(command)) return statusAfterCommand;
  if (!serverStarted) return 'Stopped';
  // A build that failed after the line (its last steps) is not running.
  return command === 'build' && code !== 0 ? 'Stopped' : null;
}

module.exports = { statusAfterClose };
