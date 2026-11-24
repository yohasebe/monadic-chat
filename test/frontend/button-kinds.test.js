/**
 * @jest-environment jsdom
 */
// Buttons take one of the kinds of the Web UI, filled: blue (confirm),
// grey (act, move about, cancel), red (delete) and yellow (a standing action
// of the side column); in a toolbar or a switch, btn-tool (clear on its
// group's panel, the chosen one filled). A white button with only a border, or another
// colour, is used only where the border or the colour itself says
// something, listed here.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../../docker/services/ruby');
const FILES = ['views/index.erb'].concat(
  fs.readdirSync(path.join(ROOT, 'public/js/monadic')).filter((f) => f.endsWith('.js')).map((f) => `public/js/monadic/${f}`),
  ['public/js/monadic.js']
);
const OTHER_KINDS = /\bbtn-(outline-[a-z]+|light|dark|success|info)\b/;
// Where another kind is meant, by what the line holds.
const EXCEPTIONS = [
  // The top bar's controls sit on the bar itself.
  /id="(cancel_query|toggle-menu)" class="btn btn-light/,
];

describe('button kinds', () => {
  test.each(FILES)('%s uses only the kinds of the Web UI, but where listed', (file) => {
    const odd = fs.readFileSync(path.join(ROOT, file), 'utf8').split('\n')
      .map((line, i) => [i + 1, line])
      .filter(([, line]) => OTHER_KINDS.test(line) && !EXCEPTIONS.some((rule) => rule.test(line)))
      .map(([n, line]) => `${file}:${n}: ${line.trim()}`);
    expect(odd).toEqual([]);
  });

  test('each exception still names something there', () => {
    const all = FILES.map((file) => fs.readFileSync(path.join(ROOT, file), 'utf8')).join('\n');
    EXCEPTIONS.forEach((rule) => expect(all).toMatch(rule));
  });
});
