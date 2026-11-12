/**
 * Playing a tune in ABC notation (abcjs synth), in the chat and on the work
 * screen, with the sounds Monadic Chat carries (vendor/soundfont, listed in
 * bin/assets_list.sh): nothing is loaded from the network.
 *
 * Only some General MIDI instruments are carried (INSTRUMENTS). A tune that
 * asks for another is played with the carried one of the same family, or
 * with the piano.
 */
(function (window) {
  'use strict';

  const SOUNDFONT_URL = '/vendor/soundfont/FluidR3_GM/';
  // General MIDI programs carried, by family (program / 8).
  const INSTRUMENTS = {
    0: 0, // piano: acoustic grand piano (also electric piano, 4)
    1: 11, // chromatic percussion: vibraphone
    2: 19, // organ: church organ
    3: 25, // guitar: steel-string acoustic (also clean electric, 27)
    4: 33, // bass: fingered electric bass
    5: 48, // strings: string ensemble
    6: 48, // ensemble: string ensemble
    7: 61, // brass: brass section
    10: 80, // synth lead: square
    11: 89 // synth pad: warm
  };
  const CARRIED = new Set([0, 4, 11, 19, 25, 27, 33, 48, 61, 80, 89]);

  // The program a tune's program is played with.
  function carriedProgram(program) {
    if (CARRIED.has(program)) return program;
    const family = INSTRUMENTS[Math.floor(program / 8)];
    return family === undefined ? 0 : family;
  }

  // The tune with each instrument it asks for (%%MIDI program [channel] n,
  // also inline as [I:MIDI program n]) set to one carried.
  function playableText(text) {
    return String(text).replace(/(MIDI\s*=?\s*program\s+)(\d+)(\s+(\d+))?/g, (all, head, first, rest, second) => {
      if (second !== undefined) return `${head}${first} ${carriedProgram(Number(second))}`;
      return `${head}${carriedProgram(Number(first))}`;
    });
  }

  // Playing controls for a tune (abcjs's), in holder. cursor: abcjs cursor
  // control, or null. Returns the synth controller, or null when the
  // browser cannot play.
  function attach(holder, visualObj, cursor) {
    if (!window.ABCJS || !window.ABCJS.synth.supportsAudio()) return null;
    const control = new window.ABCJS.synth.SynthController();
    control.load(holder, cursor || null, {
      displayLoop: true, displayRestart: true, displayPlay: true, displayProgress: true, displayWarp: true
    });
    control.setTune(visualObj, false, { soundFontUrl: SOUNDFONT_URL });
    return control;
  }

  // A tune of the work screen: its controls in holder, from its text (the
  // score itself is drawn apart, as an image). Returns { stop() }.
  async function playerFor(holder, text) {
    if (window.LazyLoader) await window.LazyLoader.abcjs();
    if (!window.ABCJS) return { stop() {} };
    const tunes = window.ABCJS.renderAbc('*', playableText(text));
    const control = tunes && tunes[0] ? attach(holder, tunes[0], null) : null;
    return { stop() { if (control) control.pause(); } };
  }

  const api = { SOUNDFONT_URL, playableText, carriedProgram, attach, playerFor };
  window.AbcPlayer = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
