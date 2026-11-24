/**
 * sts-stream-worklet.js
 *
 * The player of a speech-to-speech (Live Conversation) answer: one node
 * that writes each piece of audio it is given at the frame given
 * ({ type: 'add', turn, start, samples }), so pieces that follow each other
 * join sample for sample, as one sound would. A frame no piece covers is
 * silence. { type: 'drop', turn } takes off what is left of a turn's pieces
 * (barge-in, a new turn); { type: 'dropAll' } takes off everything.
 *
 * Loaded by ws-sts-playback.js with audioWorklet.addModule; it runs in the
 * AudioWorkletGlobalScope (currentFrame, AudioWorkletProcessor,
 * registerProcessor).
 */
class StsStreamPlayer extends AudioWorkletProcessor {
  constructor() {
    super();
    // { turn, start, samples }, in the order of their start.
    this.pieces = [];
    this.port.onmessage = (event) => {
      const message = event.data || {};
      if (message.type === 'add' && message.samples && message.samples.length > 0) {
        this.pieces.push({ turn: message.turn, start: message.start, samples: message.samples });
        this.pieces.sort((a, b) => a.start - b.start);
      } else if (message.type === 'drop') {
        this.pieces = this.pieces.filter((piece) => piece.turn !== message.turn);
      } else if (message.type === 'dropAll') {
        this.pieces = [];
      }
    };
  }

  process(_inputs, outputs) {
    const channels = outputs[0];
    if (!channels || channels.length === 0) return true;
    const out = channels[0];
    const from = currentFrame;
    const to = from + out.length;
    out.fill(0);
    // What has been heard is let go.
    this.pieces = this.pieces.filter((piece) => piece.start + piece.samples.length > from);
    for (const piece of this.pieces) {
      if (piece.start >= to) break;
      const first = Math.max(from, piece.start);
      const last = Math.min(to, piece.start + piece.samples.length);
      for (let frame = first; frame < last; frame++) out[frame - from] += piece.samples[frame - piece.start];
    }
    for (let c = 1; c < channels.length; c++) channels[c].set(out);
    return true;
  }
}

registerProcessor('sts-stream-player', StsStreamPlayer);
