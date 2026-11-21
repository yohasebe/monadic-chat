/**
 * @jest-environment jsdom
 */

// The Web Search toggle goes with a message as the user set it: whether the
// model can search is decided where the request is made.
const fs = require('fs');
const path = require('path');

function setParamsBody() {
  const source = fs.readFileSync(
    path.join(__dirname, '..', '..', 'docker/services/ruby/public/js/monadic/utilities.js'), 'utf8'
  );
  const start = source.search(/function\s+setParams\s*\(/);
  const open = source.indexOf('{', start);
  let depth = 1;
  let i = open + 1;
  while (i < source.length && depth > 0) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}') depth--;
    i++;
  }
  return source.slice(open + 1, i - 1);
}

describe('setParams and the Web Search toggle', () => {
  // The params of a message, the page holding the given model and toggle.
  function paramsOf(spec, checked) {
    document.body.innerHTML = `
      <select id="apps"><option value="ChatApp" selected>Chat</option></select>
      <select id="model"><option value="the-model" selected>the-model</option></select>
      <input type="checkbox" id="websearch" ${checked ? 'checked' : ''}>`;
    const run = new Function(
      '$id', 'apps', 'modelSpec', 'DEFAULT_MAX_OUTPUT_TOKENS', 'DEFAULT_CONTEXT_SIZE', 'DEFAULT_MAX_INPUT_TOKENS',
      'maxInputTokensOf',
      `let params; ${setParamsBody()}; return params;`
    );
    const modelSpec = { 'the-model': spec };
    window.modelSpec = modelSpec;
    return run((id) => document.getElementById(id), { ChatApp: { group: 'Google' } }, modelSpec, 4000, 100, 4000,
               () => 4000);
  }

  it('is on for a model that searches by itself and takes no tools', () => {
    expect(paramsOf({ supports_web_search: true }, true).websearch).toBe(true);
  });

  it('is on for a model the page knows nothing of', () => {
    expect(paramsOf(undefined, true).websearch).toBe(true);
  });

  it('is off when the toggle is off, whatever the model can do', () => {
    expect(paramsOf({ tool_capability: true, supports_web_search: true }, false).websearch).toBe(false);
  });
});
