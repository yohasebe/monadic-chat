const modelSpec = {
  // gpt-5 models
  "gpt-5": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimum", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-5-2025-08-07": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimum", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-5-mini": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimum", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-5-mini-2025-08-07": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimum", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-5-nano": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimum", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-5-nano-2025-08-07": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimum", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  // gpt-4.1 models
  "gpt-4.1": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4.1-2025-04-14": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4.1-mini": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4.1-mini-2025-04-14": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4.1-nano": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-4.1-nano-2025-04-14": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "gpt-5-chat-latest": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimum", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
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
  "o3-pro-2025-06-10": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "o3-pro": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "o4-mini": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "o4-mini-2025-04-16": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "o3": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "o3-2025-04-16": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "o3-mini": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": false
  },
  "o3-mini-2025-01-31": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": false
  },
  "o1": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": false
  },
  "o1-2024-12-17": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": false
  },
  "o1-mini": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [25000, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": false
  },
  "o1-mini-2024-09-12": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [25000, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": false
  },
  "o1-pro": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "o1-pro-2025-03-19": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  // O3 series models
  "o3": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "low"]
  },
  "o3-2025-04-16": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "low"]
  },
  "o3-pro": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "medium"]
  },
  "o3-pro-2025-06-10": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "high"]
  },
  "o3-mini": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "low"]
  },
  "o3-mini-2025-01-31": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "low"]
  },
  "o3-deep-research": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "high"]
  },
  "o3-deep-research-2025-06-26": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "high"]
  },
  // O4 series models
  "o4-mini": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "low"]
  },
  "o4-mini-2025-04-16": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "low"]
  },
  "o4-mini-deep-research": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "high"]
  },
  "o4-mini-deep-research-2025-06-26": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "high"]
  },
  // Other OpenAI models
  "codex-mini-latest": {
    "context_window": [1, 128000],
    "max_output_tokens": [1, 16384],
    "temperature": [[0.0, 2.0], 0.7],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "gpt-4": {
    "context_window": [1, 8192],
    "max_output_tokens": [1, 4096],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": false
  },
  "gpt-4o-mini-transcribe": {
    "context_window": [1, 128000],
    "max_output_tokens": [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": false,
    "vision_capability": false
  },
  "gpt-4o-transcribe": {
    "context_window": [1, 128000],
    "max_output_tokens": [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": false,
    "vision_capability": false
  },
  // Anthropic models
  "claude-opus-4-1-20250805": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [[1, 32000], 32000],
    "reasoning_effort": [["none", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-opus-4-20250514": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [[1, 32000], 32000],
    "reasoning_effort": [["none", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-sonnet-4-20250514": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [[1, 64000], 64000],
    "reasoning_effort": [["none", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-7-sonnet-20250219": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [[1, 64000], 64000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-5-sonnet-20240620": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-5-sonnet-20241022": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-5-haiku-20241022": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "vision_capability": false
  },
  "claude-3-opus-20240229": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 4096],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "claude-3-haiku-20240307": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 4096],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": false
  },
  // Cohere models
  "command-a-vision-07-2025": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 8000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "command-a-03-2025": {
    "context_window" : [1, 256000],
    "max_output_tokens" : [1, 8000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true
  },
  "command-r7b-12-2024": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true
  },
  "c4ai-aya-vision-32b": {
    "context_window" : [1, 16000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "vision_capability": true
  },
  "command-r7b-arabic-02-2025": {
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
  "command-r-08-2024": {
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
  "command-nightly": {
    "context_window" : [1, 128000],
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
  "c4ai-aya-expanse-32b": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
  },
  // Gemini models
  "gemini-2.5-flash-lite-06-17": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.5-flash-lite": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.5-flash": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.5-flash-lite-preview-06-17": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.5-flash-preview-05-20": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.5-pro": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.5-pro-preview-06-05": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.5-pro-preview-05-06": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.5-pro-preview-03-25": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  // Experimental models
  "gemini-2.5-pro-exp": {
    "context_window" : [1, 1000000],
    "max_output_tokens" : [1, 64000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.5-pro-exp-03-25": {
    "context_window" : [1, 1000000],
    "max_output_tokens" : [1, 64000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true
  },
  "gemini-2.0-pro-exp-02-05": {
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
  "mistral-ocr-latest": {
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "vision_capability": true
  },
  "voxtral-small-latest": {
    "context_window" : [1, 32000],
    "max_output_tokens" : [1, 32000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0]
  },
  "voxtral-mini-latest": {
    "context_window" : [1, 32000],
    "max_output_tokens" : [1, 32000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0]
  },
  "magistral-small-latest": {
    "context_window" : [1, 40000],
    "max_output_tokens" : [1, 40000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0]
  },
  "magistral-medium-latest": {
    "context_window" : [1, 40000],
    "max_output_tokens" : [1, 40000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0]
  },
  "devstral-medium-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 128000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "devstral-small-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 128000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "open-mixtral-8x22b": {
    "max_output_tokens" : [1, 65536],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "open-mixtral-8x7b": {
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
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
  "pixtral-12b-latest": {
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "vision_capability": true
  },
  "mistral-small-latest": {
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "mistral-medium-latest": {
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  // Non-latest pixtral and mistral models
  "pixtral-12b": {
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "mistral-small": {
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "mistral-medium": {
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
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
  "ministral-8b-latest": {
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
  // xAI models
  "grok-4-0709": {
    "context_window" : [1, 256000],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "reasoning_effort": [["low", "high"], "low"],
    "vision_capability": true
  },
  "grok-3": {
    "context_window" : [1, 131072],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "reasoning_effort": [["low", "high"], "low"]
  },
  "grok-3-mini": {
    "context_window" : [1, 131072],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "reasoning_effort": [["low", "high"], "low"]
  },
  "grok-3-fast": {
    "context_window" : [1, 131072],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "reasoning_effort": [["low", "high"], "low"]
  },
  "grok-3-mini-fast": {
    "context_window" : [1, 131072],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "reasoning_effort": [["low", "high"], "low"]
  },
  "grok-2-vision-1212": {
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
  // Perplexity models
  "r1-1776": {
    "context_window" : [1, 128000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "reasoning_model": true
  },
  "sonar-deep-research": {
    "context_window" : [1, 128000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "reasoning_model": true,
  },
  "sonar-reasoning-pro": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 8000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0],
    "vision_capability": true
  },
  "sonar-reasoning": {
    "context_window" : [1, 128000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0],
    "vision_capability": true
  },
  "sonar-pro": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 8000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0],
    "vision_capability": true
  },
  "sonar": {
    "context_window" : [1, 128000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0],
    "vision_capability": true
  },
  // DeepSeek models
  "deepseek-chat": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0], 
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "deepseek-reasoner": {
    "context_window" : [1, 64000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0], 
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    // "tool_capability": true
  },
}

// Expose modelSpec globally for browser environment
if (typeof window !== 'undefined') {
  window.modelSpec = modelSpec;
}

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = modelSpec;
}
