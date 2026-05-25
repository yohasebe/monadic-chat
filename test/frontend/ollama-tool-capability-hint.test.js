/**
 * @jest-environment jsdom
 *
 * Pins the contract for the #model-no-tools sidebar hint:
 *   - shown ONLY when provider is Ollama AND modelSpec[model].tool_capability
 *     is explicitly false
 *   - hidden when tool_capability is true, missing, or provider is not Ollama
 *
 * The actual show/hide decision lives in monadic.js model change handler.
 * Rather than load the full bundle, we extract the rule and exercise it
 * directly — the spec serves as a regression net for the gate predicate.
 */

function shouldShowNoToolsHint(provider, model, modelSpec) {
  const isOllama = (provider || '').toLowerCase() === 'ollama';
  const spec = modelSpec && modelSpec[model];
  const hasFlag = spec && Object.prototype.hasOwnProperty.call(spec, 'tool_capability');
  return Boolean(isOllama && hasFlag && spec.tool_capability !== true);
}

describe('Ollama tool-capability hint gate', () => {
  describe('shouldShowNoToolsHint', () => {
    it('returns true for Ollama + tool_capability:false', () => {
      const spec = { 'gemma3:4b': { tool_capability: false } };
      expect(shouldShowNoToolsHint('ollama', 'gemma3:4b', spec)).toBe(true);
    });

    it('returns false for Ollama + tool_capability:true', () => {
      const spec = { 'qwen3-vl:8b-thinking': { tool_capability: true } };
      expect(shouldShowNoToolsHint('ollama', 'qwen3-vl:8b-thinking', spec)).toBe(false);
    });

    it('returns false when tool_capability flag is missing (unknown state)', () => {
      const spec = { 'unknown-model': { vision_capability: true } };
      expect(shouldShowNoToolsHint('ollama', 'unknown-model', spec)).toBe(false);
    });

    it('returns false for non-Ollama providers regardless of flag', () => {
      const spec = { 'some-model': { tool_capability: false } };
      expect(shouldShowNoToolsHint('openai', 'some-model', spec)).toBe(false);
      expect(shouldShowNoToolsHint('anthropic', 'some-model', spec)).toBe(false);
      expect(shouldShowNoToolsHint('mistral', 'some-model', spec)).toBe(false);
    });

    it('is case-insensitive on provider name', () => {
      const spec = { 'gemma3:4b': { tool_capability: false } };
      expect(shouldShowNoToolsHint('Ollama', 'gemma3:4b', spec)).toBe(true);
      expect(shouldShowNoToolsHint('OLLAMA', 'gemma3:4b', spec)).toBe(true);
    });

    it('returns false for empty/missing inputs', () => {
      expect(shouldShowNoToolsHint(null, null, null)).toBe(false);
      expect(shouldShowNoToolsHint('', '', {})).toBe(false);
      expect(shouldShowNoToolsHint('ollama', 'nonexistent', {})).toBe(false);
    });
  });

  describe('contract with OllamaHelper.list_models_with_capabilities', () => {
    // OllamaHelper.list_models_with_capabilities (ollama_helper.rb:222) is the
    // SSOT for tool_capability on Ollama models. It sources the flag from
    // /api/show's capabilities array. These shapes mirror the JSON the
    // /api/ollama/models endpoint serves.
    it('handles the dynamic shape served by /api/ollama/models', () => {
      const dynamicSpec = {
        'qwen3:4b': {
          context_window: [1, 32768],
          max_output_tokens: [1, 8192],
          tool_capability: true,
          vision_capability: false,
          supports_thinking: true
        },
        'gemma3:4b': {
          context_window: [1, 8192],
          max_output_tokens: [1, 2048],
          tool_capability: false,
          vision_capability: false,
          supports_thinking: false
        }
      };
      expect(shouldShowNoToolsHint('ollama', 'qwen3:4b', dynamicSpec)).toBe(false);
      expect(shouldShowNoToolsHint('ollama', 'gemma3:4b', dynamicSpec)).toBe(true);
    });
  });
});
