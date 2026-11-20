// The layer lines of an image download, read the way Docker and Podman print
// them, summed into one figure.
const { createPullProgress, formatBytes } = require('../../app/pull_progress');

describe('image download progress', () => {
  test('sums the latest size of each layer from Podman-style lines', () => {
    const pulls = createPullProgress();
    ['683a6a24624c Downloading 433.2MB', 'd2a21abf354f Downloading 491.6MB',
      '683a6a24624c Downloading 1.148GB', 'af0735533345 Downloading 26.12MB'].forEach((line) => {
      expect(pulls.take(line)).toBe(true);
    });
    expect(pulls.progress()).toMatchObject({ layers: 3, bytes: 1148000000 + 491600000 + 26120000 });
  });

  test('reads Docker-style lines, with or without a bar and a total', () => {
    const pulls = createPullProgress();
    expect(pulls.take('683a6a24624c: Pulling fs layer')).toBe(true);
    expect(pulls.take('683a6a24624c: Downloading [====>      ]  12.5MB/45MB')).toBe(true);
    expect(pulls.take('d2a21abf354f: Already exists')).toBe(true);
    expect(pulls.progress()).toMatchObject({ layers: 2, bytes: 12500000 });
  });

  test('leaves every other line to the console', () => {
    const pulls = createPullProgress();
    ['Starting all Monadic Chat containers...', ' ✔ qdrant_service Pulled', 'ERROR: pull access denied']
      .forEach((line) => expect(pulls.take(line)).toBe(false));
    expect(pulls.active()).toBe(false);
  });

  test('takes the layer lines out of a block of many lines and keeps the rest', () => {
    const pulls = createPullProgress();
    const layers = Array.from({ length: 40 }, (_, i) => ` d2a21abf354f Downloading ${(1.7 + i / 1000).toFixed(3)}GB`);
    const block = ['Starting Python image build (atomic) . . .', ...layers, ' 683a6a24624c Download complete 0B', ''].join('\n');
    const { rest, took } = pulls.filter(block);
    expect(took).toBe(true);
    expect(rest).toBe('Starting Python image build (atomic) . . .\n');
    expect(pulls.progress().bytes).toBe(1739000000);
    expect(pulls.filter(layers.join('\n') + '\n')).toEqual({ rest: '', took: true });
  });

  test('starts again after a reset', () => {
    const pulls = createPullProgress();
    pulls.take('683a6a24624c Downloading 10MB');
    pulls.reset();
    expect(pulls.active()).toBe(false);
  });

  test('writes sizes the way the console shows them', () => {
    expect(formatBytes(1234000000)).toBe('1.23 GB');
    expect(formatBytes(56700000)).toBe('57 MB');
    expect(formatBytes(800)).toBe('1 kB');
  });
});
