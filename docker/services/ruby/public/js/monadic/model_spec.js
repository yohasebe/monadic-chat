const modelSpec = {
  // Opena AI models
  // gpt-4o models
  "gpt-4o": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4o-2024-08-06": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4o-2024-11-20": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4o-2024-05-13": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4096],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "chatgpt-4o-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4o-mini": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4o-mini-2024-07-18": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  // reasoning models
  "o1": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 100000],
    "reasoning_effort": [["low", "medium", "high"], "medium"],
    "tool_capability": true,
    "vision_capability": true
  },
  "o1-2024-12-17": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 100000],
    "reasoning_effort": [["low", "medium", "high"], "medium"],
    "tool_capability": true,
    "vision_capability": true
  },
  "o3-mini": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 100000],
    "reasoning_effort": [["low", "medium", "high"], "medium"],
    "tool_capability": true,
    "vision_capability": false
  },
  "o3-mini-2025-01-31": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 100000],
    "reasoning_effort": [["low", "medium", "high"], "medium"],
    "tool_capability": true,
    "vision_capability": false
  },
  // Anthropic models
  "claude-3-5-sonnet-20241022": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 8192],
    "temperature": [0.0, 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-5-sonnet-latest": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 8192],
    "temperature": [0.0, 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-5-haiku-20241022": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 8192],
    "temperature": [0.0, 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": false
  },
  "claude-3-5-haiku-latest": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 8192],
    "temperature": [0.0, 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": false
  },
  "claude-3-opus-20240229": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 4096],
    "temperature": [0.0, 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-opus-latest": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 4096],
    "temperature": [0.0, 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-sonnet-20240229": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 4096],
    "temperature": [0.0, 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-haiku-20240307": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 4096],
    "temperature": [0.0, 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": false
  },
  // Cohere models
  "command-r7b-12-2024": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true
  },
  "command-r-plus-08-2024": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true
  },
  "command-r-plus-04-2024": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true
  },
  "command-r-plus": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true
  },
  "command-r-08-2024": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true
  },
  "command-r-03-2024": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true
  },
  "command-r": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true
  },
  "command": {
    "context_window" : [1, 4000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
  },
  "command-nightly": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
  },
  "command-light": {
    "context_window" : [1, 4000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
  },
  "command-light-nightly": {
    "context_window" : [1, 4000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
  },
  "c4ai-aya-expanse-8b": {
    "context_window" : [1, 8000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
  },
  "c4ai-aya-expanse-32b": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
  },
  // Gemini models
  // Experimental models
  "gemini-2.0-pro-exp": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  "gemini-2.0-pro-exp": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  "gemini-2.0-pro-exp-02-05": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  "gemini-2.0-flash-thinking-exp": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  "gemini-2.0-flash-thinking-exp-1219": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  "gemini-2.0-flash-thinking-exp-01-21": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  // Flash models
  "gemini-2.0-flash-exp": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  "gemini-2.0-flash-001": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  "gemini-2.0-flash": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  "gemini-2.0-flash-lite-preview": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  "gemini-2.0-flash-lite-preview-02-05": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
  },
  // Mistral models
  // codestral models
  "codestral-latest": {
    "max_output_tokens" : [1, 256000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "codestral-2501": {
    "max_output_tokens" : [1, 256000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "codestral-2411-rc5": {
    "max_output_tokens" : [1, 256000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "codestral-mamba-latest": {
    "max_output_tokens" : [1, 256000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  // mistral models
  "mistral-large-latest": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "mistral-saba-latest": {
    "max_output_tokens" : [1, 32000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
  },
  "mistral-saba-2502": {
    "max_output_tokens" : [1, 32000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
  },
  // pixtral models
  "pixtral-large-latest": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "pixtral-large-2411": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "pixtral-12b-2409": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  // ministral models
  "ministral-3b-latest": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "ministral-3b-2410": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "ministral-8b-latest": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "ministral-8b-2410": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  // open models
  "open-mistral-nemo": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "open-mistral-nemo-2407": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "open-codestral-mamba": {
    "max_output_tokens" : [1, 256000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
  },
  // xAI models
  "grok-2-vision-1212": {
    "context_window" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "grok-2-vision": {
    "context_window" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "grok-2-vision-latest": {
    "context_window" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "grok-2-1212": {
    "context_window" : [1, 131072],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "grok-2": {
    "context_window" : [1, 131072],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "grok-2-latest": {
    "context_window" : [1, 131072],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "grok-vision-beta": {
    "context_window" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "grok": {
    "context_window" : [1, 131072],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  // Perplexity models
  "sonar-reasoning-pro": {
    "context_window" : [1, 127000],
    "max_output_tokens" : [1, 127000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0]
  },
  "sonar-reasoning": {
    "context_window" : [1, 127000],
    "max_output_tokens" : [1, 127000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0]
  },
  "sonar-pro": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 127000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0]
  },
  "sonar": {
    "context_window" : [1, 127000],
    "max_output_tokens" : [1, 127000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0]
  },
  // DeepSeek models
  "deepseek-chat": {
    "context_window" : [1, 64000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0], 
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 0.0, 2.0], 0.0],
    // "tool_capability": true
  },
  "deepseek-reasoner": {
    "context_window" : [1, 32000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0], 
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 0.0, 2.0], 0.0],
    // "tool_capability": true
  },
}
