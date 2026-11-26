/**
 * @jest-environment jsdom
 */

// A message says nothing of web search: whether its answer may search is the
// server's (the setting and the chat's app).
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

describe('setParams and web search', () => {
  // The params of a message, the page holding the given model.
  function paramsOf(spec) {
    document.body.innerHTML = `
      <select id="apps"><option value="ChatApp" selected>Chat</option></select>
      <select id="model"><option value="the-model" selected>the-model</option></select>`;
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

  it('sends no web search setting with a message, whatever the model can do', () => {
    expect(paramsOf({ supports_web_search: true, tool_capability: true })).not.toHaveProperty('websearch');
    expect(paramsOf(undefined)).not.toHaveProperty('websearch');
  });
});
