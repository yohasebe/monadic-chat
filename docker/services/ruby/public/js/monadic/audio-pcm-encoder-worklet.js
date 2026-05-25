// AudioWorklet processor that captures mono Float32 frames from the input
// stream, resamples them to a target rate (default 24000 Hz), converts each
// sample to little-endian Int16, and posts chunks of approximately
// `frameMs` milliseconds (default 100 ms) as transferable ArrayBuffers.
//
// Loaded via `audioCtx.audioWorklet.addModule(...)` from recording.js when
// the realtime streaming STT path is active.
class PCMEncoder extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const opts = (options && options.processorOptions) || {};
    this.targetRate = opts.targetRate || 24000;
    this.frameMs = opts.frameMs || 100;
    this.ratio = sampleRate / this.targetRate;
    this.samplesPerChunk = Math.max(1, Math.round(this.targetRate * this.frameMs / 1000));
    this.outBuf = [];
    this.readPos = 0;
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || input.length === 0) return true;
    const ch = input[0];
    if (!ch || ch.length === 0) return true;

    let i = this.readPos;
    while (i < ch.length) {
      const idx = Math.floor(i);
      const sample = ch[idx];
      const s = sample > 1 ? 1 : (sample < -1 ? -1 : sample);
      this.outBuf.push(s < 0 ? Math.round(s * 0x8000) : Math.round(s * 0x7FFF));
      i += this.ratio;
    }
    this.readPos = i - ch.length;

    while (this.outBuf.length >= this.samplesPerChunk) {
      const samples = this.outBuf.splice(0, this.samplesPerChunk);
      const arr = new Int16Array(samples);
      this.port.postMessage(arr.buffer, [arr.buffer]);
    }
    return true;
  }
}

registerProcessor('pcm-encoder', PCMEncoder);
