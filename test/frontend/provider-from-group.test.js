/**
 * The provider an app's group names (getProviderFromGroup in monadic.js),
 * and the AI User panel's badge, which takes it from there.
 */

const fs = require('fs');
const path = require('path');

const JS = path.join(__dirname, '../../docker/services/ruby/public/js');
const main = fs.readFileSync(path.join(JS, 'monadic.js'), 'utf8');

function loadHelper() {
  const start = main.indexOf('function getProviderFromGroup(group) {');
  const end = main.indexOf('\n}\n', start);
  // eslint-disable-next-line no-new-func
  return new Function(`${main.slice(start, end + 2)}; return getProviderFromGroup;`)();
}

describe('getProviderFromGroup', () => {
  const provider = loadHelper();

  test.each([
    ['Anthropic', 'Anthropic'], ['Google', 'Google'], ['Cohere', 'Cohere'], ['Mistral', 'Mistral'],
    ['Pixtral', 'Mistral'], ['Devstral', 'Mistral'], ['DeepSeek', 'DeepSeek'], ['xAI', 'xAI'],
    ['Ollama', 'Ollama'], ['OpenAI', 'OpenAI'], [null, 'OpenAI']
  ])('%s is %s', (group, expected) => {
    expect(provider(group)).toBe(expected);
  });

  test('is what both writers of the AI User badge use', () => {
    const utilities = fs.readFileSync(path.join(JS, 'monadic/utilities.js'), 'utf8');
    [main, utilities].forEach((source) => {
      const at = source.indexOf('ai-assistant-provider');
      const before = source.slice(Math.max(0, at - 1500), at);
      expect(before).toContain('getProviderFromGroup(');
      expect(before).not.toMatch(/includes\("anthropic"\)/);
    });
  });
});
