// A warning that shares a chunk of monadic.sh output with a message shown as
// its translation must not disappear with it.
const { keepWarnings, createLineBuffer } = require('../../app/build_output');

const WARNING = "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color:#FF7F07;'></i> The Privacy Filter image could not be downloaded (check the network); the one already installed stays in use.</p>";

describe('keeping warnings when a chunk is translated', () => {
  test('keeps a warning that came in the same chunk as a success message', () => {
    const chunk = `${WARNING}\n[INFO] Privacy container build succeeded.\n`;
    const shown = keepWarnings(chunk, '[HTML]: <p>Privacy Filter is ready.</p>');
    expect(shown).toBe(`${WARNING}\n[HTML]: <p>Privacy Filter is ready.</p>`);
  });

  test('leaves a chunk shown as it came alone', () => {
    expect(keepWarnings(WARNING, WARNING)).toBe(WARNING);
  });

  test('adds nothing when the replaced chunk had no warning', () => {
    expect(keepWarnings('[INFO] Privacy container build succeeded.', 'done')).toBe('done');
  });

  test('keeps a warning whose line was cut between two chunks', () => {
    // the cut falls inside the warning; the success marker comes after it
    const shown = [];
    const lines = createLineBuffer((chunk) => {
      shown.push(chunk.includes('build succeeded') ? keepWarnings(chunk, 'READY') : chunk);
    });
    const stream = `${WARNING}\n[INFO] Privacy container build succeeded.\n`;
    const at = stream.indexOf('or:#FF7F07');
    lines.push(stream.slice(0, at));
    lines.push(stream.slice(at));
    lines.flush();
    expect(shown).toEqual([`${WARNING}\nREADY`]);
  });

  test('passes on whole lines, and what is left when the output ends', () => {
    const got = [];
    const lines = createLineBuffer((chunk) => got.push(chunk));
    lines.push('one\ntw');
    lines.push('o\nthr');
    lines.flush();
    expect(got).toEqual(['one\n', 'two\n', 'thr']);
  });

  test('main.js passes every chunk through it', () => {
    const main = require('fs').readFileSync(require('path').join(__dirname, '../../app/main.js'), 'utf8');
    expect(main).toMatch(/writeToScreen\(keepWarnings\(output, translatedOutput\)\);/);
    expect(main).toMatch(/const stdoutLines = createLineBuffer\(function \(output\) \{/);
    expect(main).toMatch(/subprocess\.on\('close', function \(code\) \{\n\s*stdoutLines\.flush\(\);/);
  });
});
