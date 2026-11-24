/**
 * @jest-environment jsdom
 */
// The Live Conversation's player node: it writes each piece at its frame,
// so pieces that follow each other join sample for sample; a frame no piece
// covers is silence, and a dropped turn is not heard.
const path = require('path');

const FILE = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/sts-stream-worklet.js');

describe('sts-stream-player', () => {
  let Player;

  beforeEach(() => {
    global.AudioWorkletProcessor = class { constructor() { this.port = {}; } };
    global.registerProcessor = (name, cls) => { if (name === 'sts-stream-player') Player = cls; };
    jest.isolateModules(() => { require(FILE); });
  });

  afterEach(() => {
    delete global.AudioWorkletProcessor;
    delete global.registerProcessor;
    delete global.currentFrame;
  });

  // Renders blocks of `size` frames from frame `from`, as the audio thread
  // does; returns the frames written, in order.
  function render(player, from, blocks, size = 4) {
    const frames = [];
    for (let b = 0; b < blocks; b++) {
      global.currentFrame = from + b * size;
      const out = [new Float32Array(size)];
      expect(player.process([], [out])).toBe(true);
      frames.push(...out[0]);
    }
    return frames;
  }

  const add = (player, turn, start, values) =>
    player.port.onmessage({ data: { type: 'add', turn, start, samples: Float32Array.from(values) } });

  test('writes pieces that follow each other as one sound, across blocks', () => {
    const player = new Player();
    add(player, 't1', 2, [1, 2, 3]);
    add(player, 't1', 5, [4, 5]);
    add(player, 't1', 7, [6]);
    expect(render(player, 0, 3)).toEqual([0, 0, 1, 2, 3, 4, 5, 6, 0, 0, 0, 0]);
  });

  test('leaves silence where no piece is, and plays a piece given out of order at its frame', () => {
    const player = new Player();
    add(player, 't1', 6, [9]);
    add(player, 't1', 1, [7]);
    expect(render(player, 0, 2)).toEqual([0, 7, 0, 0, 0, 0, 9, 0]);
  });

  test('drops what is left of a turn, and everything', () => {
    const player = new Player();
    add(player, 't1', 0, [1, 1, 1, 1, 1, 1]);
    add(player, 't2', 6, [2, 2]);
    expect(render(player, 0, 1)).toEqual([1, 1, 1, 1]);
    player.port.onmessage({ data: { type: 'drop', turn: 't1' } });
    expect(render(player, 4, 1)).toEqual([0, 0, 2, 2]);
    add(player, 't3', 8, [3]);
    player.port.onmessage({ data: { type: 'dropAll' } });
    expect(render(player, 8, 1)).toEqual([0, 0, 0, 0]);
  });

  test('lets go of what has been heard, and writes every channel alike', () => {
    const player = new Player();
    add(player, 't1', 0, [1, 2]);
    // Heard in the first block; let go when the next one is written.
    render(player, 0, 2);
    expect(player.pieces).toHaveLength(0);
    add(player, null, 8, [5]);
    global.currentFrame = 8;
    const out = [new Float32Array(2), new Float32Array(2)];
    player.process([], [out]);
    expect([...out[0]]).toEqual([5, 0]);
    expect([...out[1]]).toEqual([5, 0]);
  });
});
