/**
 * @jest-environment jsdom
 */

// An Ollama app chosen after the page loaded shows the models installed now.
describe('refreshOllamaModels', () => {
  let installed;

  beforeEach(async () => {
    jest.resetModules();
    installed = { 'gpt-oss:20b': { tool_capability: true } };
    global.fetch = jest.fn((url) => Promise.resolve({
      ok: true,
      json: () => Promise.resolve(url === '/api/ollama/models' ? { models: installed } : {})
    }));
    window.modelSpec = {};
    window.apps = {
      ChatOllama: { group: 'Ollama', models: JSON.stringify(['gpt-oss:20b']) },
      CodingAssistantOllama: { group: 'Ollama', models: JSON.stringify(['gpt-oss:20b']) },
      ChatOpenAI: { group: 'OpenAI', models: JSON.stringify(['gpt-6.1-sol']) }
    };
    window.proceedWithAppChange = jest.fn();
    require('../../docker/services/ruby/public/js/monadic/model_loader.js');
    // The page's own first load of the models is done before each case.
    await new Promise((resolve) => setTimeout(resolve, 0));
    global.fetch.mockClear();
  });

  it('leaves the app as it is when the installed models are the same', async () => {
    expect(await window.refreshOllamaModels('ChatOllama')).toBe(false);
    expect(window.proceedWithAppChange).not.toHaveBeenCalled();
  });

  it('gives every Ollama app the models installed now and sets the chosen app up again', async () => {
    installed['qwen3:30b'] = { tool_capability: true };
    expect(await window.refreshOllamaModels('ChatOllama')).toBe(true);
    expect(JSON.parse(window.apps.ChatOllama.models)).toEqual(['gpt-oss:20b', 'qwen3:30b']);
    expect(JSON.parse(window.apps.CodingAssistantOllama.models)).toEqual(['gpt-oss:20b', 'qwen3:30b']);
    expect(JSON.parse(window.apps.ChatOpenAI.models)).toEqual(['gpt-6.1-sol']);
    expect(window.modelSpec['qwen3:30b']).toEqual({ tool_capability: true });
    expect(window.proceedWithAppChange).toHaveBeenCalledWith('ChatOllama');
  });

  it('does nothing for an app of another provider', async () => {
    expect(await window.refreshOllamaModels('ChatOpenAI')).toBe(false);
    expect(global.fetch).not.toHaveBeenCalledWith('/api/ollama/models');
  });
});
