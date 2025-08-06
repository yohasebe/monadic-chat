# Custom Model Configuration

Monadic Chat allows you to customize model specifications by creating a custom `models.json` file. This feature enables you to:

- Add new models that are not yet included in the default configuration
- Override parameters of existing models
- Customize default values for temperature, max tokens, etc.

## Setup

1. Create a file named `models.json` in your Monadic Chat configuration directory:
   ```
   ~/monadic/config/models.json
   ```

2. Add your custom model definitions or overrides in JSON format.

## File Format

The `models.json` file should contain a JSON object where:
- Keys are model names (e.g., "gpt-4", "claude-3-opus")
- Values are model specification objects

## Examples

### Adding a New Model

```json
{
  "gpt-5-preview": {
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

### Overriding Existing Model Parameters

You can override specific parameters of existing models without redefining the entire specification:

```json
{
  "gpt-4": {
    "temperature": [[0.0, 2.0], 0.7],
    "max_output_tokens": [1, 8192]
  },
  "claude-3-opus-20240229": {
    "temperature": [[0.0, 1.0], 0.5]
  }
}
```

## Parameter Reference

### Common Parameters

- **context_window**: `[min, max]` - Token limit for input context
- **max_output_tokens**: `[min, max]` or `[[min, max], default]` - Maximum tokens in response
- **temperature**: `[[min, max], default]` - Creativity/randomness control
- **top_p**: `[[min, max], default]` - Nucleus sampling parameter
- **presence_penalty**: `[[min, max], default]` - Penalty for repeating topics
- **frequency_penalty**: `[[min, max], default]` - Penalty for repeating exact words

### Capability Flags

- **tool_capability**: `boolean` - Whether the model supports function calling
- **vision_capability**: `boolean` - Whether the model can process images
- **reasoning_effort**: `[options_array, default]` - For models with thinking/reasoning modes

## How It Works

1. When Monadic Chat starts, it loads the default `model_spec.js`
2. If `~/monadic/config/models.json` exists, it merges your custom specifications
3. Custom specifications override default values using deep merge
4. The merged configuration is used throughout the application

## Troubleshooting

### Invalid JSON Error

If you see an error about invalid JSON:
1. Validate your JSON syntax using a JSON validator
2. Check for trailing commas (not allowed in JSON)
3. Ensure all strings are in double quotes

### Models Not Appearing

If your custom models don't appear:
1. Check the browser console for error messages
2. Verify the file is in the correct location: `~/monadic/config/models.json`
3. Restart the Monadic Chat server after making changes

### Development vs Production

- **Development** (`rake server:debug`): Reads from `~/monadic/config/models.json`
- **Production** (Docker): Reads from `/monadic/config/models.json` (automatically mapped)

## Example File

A complete example file is available at:
```
docs/examples/models.json.example
```

Copy this file to `~/monadic/config/models.json` and modify as needed.