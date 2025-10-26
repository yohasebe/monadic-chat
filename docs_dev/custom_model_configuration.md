# Custom Model Configuration

Monadic Chat allows you to customize model specifications by creating a custom `models.json` file. This enables you to:

- Add new models not included in the default configuration
- Override parameters for existing models
- Customize default values for temperature, max tokens, and other settings

## When to Use Custom Model Configuration

- **New Models**: When providers release new models before Monadic Chat's `model_spec.js` is updated
- **Custom Parameters**: When you need different default values than the built-in ones
- **Testing**: When experimenting with unreleased or experimental models
- **Custom Apps**: When developing custom Monadic apps with specific model requirements

## Setup

1. Create a file named `models.json` in Monadic Chat's configuration directory:
   ```
   ~/monadic/config/models.json
   ```

2. Add your custom model definitions or overrides in JSON format.

## File Format

The `models.json` file should contain a JSON object with:
- Keys: Model IDs as published by each provider (replace placeholders with actual IDs from official documentation)
- Values: Model specification objects

## Examples

### Adding a New Model

```json
{
  "custom-openai-model": {
    "context_window": [1, 2000000],
    "max_output_tokens": [1, 200000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "medium"]
  }
}
```

> Replace placeholder keys with actual model IDs from each provider's official documentation.

### Overriding Existing Model Parameters

You can override specific parameters without redefining the entire model:

```json
{
  "replace-with-your-openai-model": {
    "temperature": [[0.0, 2.0], 0.7],
    "max_output_tokens": [1, 8192]
  },
  "replace-with-your-anthropic-model": {
    "temperature": [[0.0, 1.0], 0.5]
  }
}
```

## Parameter Reference

### Common Parameters

- **context_window**: `[min, max]` - Input context token limits
- **max_output_tokens**: `[min, max]` or `[[min, max], default]` - Maximum tokens in response
- **temperature**: `[[min, max], default]` - Controls creativity/randomness
- **top_p**: `[[min, max], default]` - Nucleus sampling parameter
- **presence_penalty**: `[[min, max], default]` - Penalty for topic repetition
- **frequency_penalty**: `[[min, max], default]` - Penalty for word repetition

### Feature Flags

- **tool_capability**: `boolean` - Whether model supports function calling
- **vision_capability**: `boolean` - Whether model can process images

### Provider-Specific Thinking/Reasoning Properties

#### OpenAI
- **reasoning_effort**: `[options array, default]` - Controls reasoning intensity
  - Example: `[["minimal", "low", "medium", "high"], "low"]`
  - For: OpenAI models that provide reasoning control (see <https://platform.openai.com/docs/models> for latest)

#### Claude (Anthropic)
- **thinking_budget**: `{min, default, max}` - Token budget for thinking
  - Example: `{"min": 1024, "default": 10000, "max": null}`
  - For: Claude models that expose thinking_budget (see <https://docs.anthropic.com/claude/docs> for latest)
- **supports_thinking**: `boolean` - Thinking feature support

#### Gemini (Google)
- **thinking_budget**: `{min, max, can_disable, presets}` - Thinking configuration with presets
  - Example with presets for reasoning_effort mapping:
    ```json
    {
      "min": 128,
      "max": 32768,
      "can_disable": false,
      "presets": {
        "minimal": 128,
        "low": 5000,
        "medium": 20000,
        "high": 28000
      }
    }
    ```

#### xAI (Grok)
- **reasoning_effort**: `[options array, default]` - Available for xAI reasoning-capable models
  - Example: `[["low", "high"], "low"]`
  - See <https://docs.x.ai/docs/models> for latest support

#### Other Providers
- **supports_reasoning_content**: `boolean` - DeepSeek reasoner support
- **is_reasoning_model**: `boolean` - Perplexity reasoning model flag
- **supports_thinking**: `boolean` - Mistral/Cohere thinking support

## How It Works

1. When Monadic Chat starts, it loads the default `model_spec.js`
2. If `~/monadic/config/models.json` exists, it merges your custom specifications
3. Custom specifications override default values using deep merge
4. The merged configuration is used throughout the application

## Troubleshooting

### Invalid JSON Errors

If you see errors about invalid JSON:
1. Validate your JSON syntax using a JSON validator
2. Check for trailing commas (not allowed in JSON)
3. Ensure all strings are wrapped in double quotes

### Model Not Appearing

If your custom model doesn't appear:
1. Check browser console for error messages
2. Verify the file is in the correct location: `~/monadic/config/models.json`
3. Restart Monadic Chat server after making changes

### Development vs. Production Environments

- **Development** (`rake server:debug`): Reads from `~/monadic/config/models.json`
- **Production** (Docker): Reads from `/monadic/config/models.json` (automatically mapped)

## Sample File

A complete sample file is available at:
```
docs/examples/models.json.example
```

Copy this file to `~/monadic/config/models.json` and modify as needed.

## Important Notes on Provider Properties

- Each provider uses its native API terminology (e.g., OpenAI uses "reasoning_effort", Claude uses "thinking_budget")
- Not all properties apply to all models within a provider
- Custom models must follow the same property conventions as their provider

## Integration with MDSL

When developing custom Monadic apps with MDSL, you can reference custom models by their ID:

```ruby
app "MyCustomApp" do
  llm do
    provider "OpenAI"
    model ["my-custom-model", "gpt-4o"]
  end
end
```

The app will use your custom model specifications from `models.json`.

## Related Documentation

- [MDSL Language Reference](./mdsl/mdsl_type_reference.md) - For creating custom apps
- [Model Spec Vocabulary](./developer/model_spec_vocabulary.md) - SSOT implementation details
