// A tune is played only with the instruments Monadic Chat carries: each
// one a tune asks for is set to a carried one of its family, or the piano.
const AbcPlayer = require('../../docker/services/ruby/public/js/monadic/abc-player.js');

describe('AbcPlayer', () => {
  test('keeps a carried instrument and plays another with one of its family, or the piano', () => {
    expect(AbcPlayer.carriedProgram(0)).toBe(0);
    expect(AbcPlayer.carriedProgram(27)).toBe(27);
    expect(AbcPlayer.carriedProgram(40)).toBe(48); // violin: strings
    expect(AbcPlayer.carriedProgram(29)).toBe(25); // overdriven guitar: guitar
    expect(AbcPlayer.carriedProgram(73)).toBe(0); // flute: no pipe is carried
    expect(AbcPlayer.carriedProgram(127)).toBe(0);
  });

  test('sets each instrument a tune asks for, with or without a channel, and inline', () => {
    const tune = 'X:1\nK:C\n%%MIDI program 40\nV:2\n%%MIDI program 2 73\n[I:MIDI program 25] CDEF|';
    expect(AbcPlayer.playableText(tune)).toBe('X:1\nK:C\n%%MIDI program 48\nV:2\n%%MIDI program 2 0\n[I:MIDI program 25] CDEF|');
    expect(AbcPlayer.playableText('X:1\nK:C\nCDEF|')).toBe('X:1\nK:C\nCDEF|');
  });

  test('plays from the sounds it carries', () => {
    expect(AbcPlayer.SOUNDFONT_URL).toBe('/vendor/soundfont/FluidR3_GM/');
  });
});
