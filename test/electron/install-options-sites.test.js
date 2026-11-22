// Each Python install option (app/install_options.config.js) reaches every
// place the build and the settings window take it from: the Dockerfile's
// ARG and its step, the compose build argument, monadic.sh's option list,
// what it reads, exports and records, and the settings window's checkbox,
// table, save and load.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const { PYTHON_OPTIONS } = require(path.join(ROOT, 'app/install_options.config.js'));

const dockerfile = read('docker/services/python/Dockerfile');
const compose = read('docker/services/python/compose.yml');
const monadicSh = read('docker/monadic.sh');
const settings = read('app/settings.html');

describe('Python install options', () => {
  test('are listed', () => {
    expect(PYTHON_OPTIONS.length).toBeGreaterThan(5);
  });

  describe.each(PYTHON_OPTIONS.map((o) => [o.env, o]))('%s', (env, option) => {
    test('is a build argument with a step of its own', () => {
      expect(dockerfile).toMatch(new RegExp(`^ARG ${env}=false$`, 'm'));
      expect(dockerfile).toContain(`"$${env}" = "true"`);
      expect(compose).toContain(`${env}: \${${env}:-false}`);
    });

    test('is read, exported and recorded by monadic.sh', () => {
      const list = monadicSh.match(/^PY_OPTIONS=\(([^)]*)\)/m);
      expect(list[1].split(/\s+/)).toContain(env);
      expect(monadicSh).toContain(`local ${env}=$(read_cfg_bool "${env}" false)`);
      expect(monadicSh).toMatch(new RegExp(`^\\s*export [^\\n]*\\b${env}\\b`, 'm'));
      expect(monadicSh).toContain(`${env}=\${${env}}`);
      expect(monadicSh).toContain(`\\"${env}\\": \${${env}}`);
    });

    test('has its checkbox, table entry, save and load in the settings window', () => {
      expect(settings).toContain(`<input type="checkbox" id="${option.id}">`);
      expect(settings).toContain(`${env}: '${option.id}'`);
      expect(settings).toContain(`${env}: document.getElementById('${option.id}').checked,`);
      expect(settings).toContain(`document.getElementById('${option.id}').checked = data.${env} == "true"`);
    });
  });
});
