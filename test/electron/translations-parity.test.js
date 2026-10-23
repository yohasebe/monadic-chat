// Every language of the desktop app has the English keys, with the same
// placeholders and the same markup, so a new message is never shown in
// English only because one file was missed.
const fs = require('fs');
const path = require('path');

const DIR = path.join(__dirname, '..', '..', 'app', 'translations');
const LANGS = ['en', 'ja', 'zh', 'ko', 'es', 'fr', 'de'];
const load = (lang) => JSON.parse(fs.readFileSync(path.join(DIR, `${lang}.json`), 'utf8'));
const flat = (o, p = '') => Object.entries(o).flatMap(([k, v]) =>
  (v && typeof v === 'object' ? flat(v, `${p}${k}.`) : [[`${p}${k}`, v]]));
const placeholders = (s) => (s.match(/{{\w+}}/g) || []).sort();
const tags = (s) => (s.match(/<\/?\w+>/g) || []).sort();

const en = new Map(flat(load('en')));

describe('desktop app translations', () => {
  test('every language file is listed here', () => {
    const files = fs.readdirSync(DIR).filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5)).sort();
    expect(files).toEqual([...LANGS].sort());
  });

  test.each(LANGS.filter((l) => l !== 'en'))('%s has exactly the English keys', (lang) => {
    const keys = flat(load(lang)).map(([k]) => k);
    expect(keys.filter((k) => !en.has(k))).toEqual([]);
    expect([...en.keys()].filter((k) => !keys.includes(k))).toEqual([]);
  });

  test.each(LANGS.filter((l) => l !== 'en'))('%s keeps each placeholder and tag', (lang) => {
    const wrong = flat(load(lang)).filter(([k, v]) => en.has(k) && (
      typeof v !== 'string' || v.trim() === '' ||
      placeholders(v).join() !== placeholders(en.get(k)).join() ||
      tags(v).join() !== tags(en.get(k)).join()));
    expect(wrong.map(([k]) => k)).toEqual([]);
  });
});
