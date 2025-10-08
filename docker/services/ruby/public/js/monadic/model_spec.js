const modelSpec = {
  // gpt-5 models
  "gpt-5": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "minimal"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_verbosity": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
  },
  "gpt-5-2025-08-07": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "minimal"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_verbosity": true,
    "api_type": "responses",
    "supports_web_search": true,
    "skip_in_progress_events": true
  },
  "gpt-5-mini": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_verbosity": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
  },
  "gpt-5-mini-2025-08-07": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_verbosity": true,
    "api_type": "responses",
    "supports_web_search": true,
    "skip_in_progress_events": true
  },
  "gpt-5-nano": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_verbosity": true,
    "api_type": "responses",
    "supports_web_search": true,
    "skip_in_progress_events": true
  },
  "gpt-5-nano-2025-08-07": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_verbosity": true,
    "api_type": "responses",
    "supports_web_search": true,
    "skip_in_progress_events": true
  },
  "gpt-5-pro": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 272000],
    "reasoning_effort": [["high"], "high"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_verbosity": true,
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": false,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true,
    "streaming_not_supported": true
  },
  "gpt-5-pro-2025-10-06": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 272000],
    "reasoning_effort": [["high"], "high"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_verbosity": true,
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": false,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true,
    "streaming_not_supported": true
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
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "api_type": "responses",
    "skip_in_progress_events": true
  },
  "gpt-4.1-2025-04-14": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "api_type": "responses",
    "skip_in_progress_events": true
  },
  "gpt-4.1-mini": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "api_type": "responses",
    "skip_in_progress_events": true
  },
  "gpt-4.1-mini-2025-04-14": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "api_type": "responses",
    "skip_in_progress_events": true
  },
  "gpt-4.1-nano": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "api_type": "responses",
    "skip_in_progress_events": true
  },
  "gpt-4.1-nano-2025-04-14": {
    "context_window" : [1, 1047576],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "api_type": "responses",
    "skip_in_progress_events": true
  },
  "gpt-5-chat-latest": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_verbosity": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
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
    "vision_capability": true,
    "supports_pdf_upload": true
  },
  "gpt-4o-2024-08-06": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf_upload": true
  },
  "gpt-4o-2024-11-20": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf_upload": true
  },
  "gpt-4o-2024-05-13": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4096],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf_upload": true
  },
  "chatgpt-4o-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
  },
  "gpt-4o-mini": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf_upload": true
  },
  "gpt-4o-mini-2024-07-18": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf_upload": true
  },
  // GPT-5-Codex (agent model for coding tasks)
  "gpt-5-codex": {
    "context_window": [1, 400000],
    "max_output_tokens": [1, 128000],
    "tool_capability": true,
    "vision_capability": false,
    "api_type": "responses",
    "supports_streaming": true,
    "supports_temperature": false,
    "supports_top_p": false,
    "supports_presence_penalty": false,
    "supports_frequency_penalty": false,
    "is_agent_model": true,
    "agent_type": "coding",
    "adaptive_reasoning": true,
    "supports_web_search": false,
    "supports_pdf": false,
    "supports_pdf_upload": false
  },
  // reasoning models
  "o4-mini": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "api_type": "responses",
    "supports_web_search": true
  },
  "o4-mini-2025-04-16": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "api_type": "responses",
    "supports_web_search": true
  },
  "o1": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "tool_capability": false,
    "vision_capability": false
  },
  "o1-2024-12-17": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "low"],
    "tool_capability": false,
    "vision_capability": false
  },
  "o1-mini": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [25000, 65536],
    "tool_capability": false,
    "vision_capability": false
  },
  "o1-mini-2024-09-12": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [25000, 65536],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "low"],
    "tool_capability": false,
    "vision_capability": false
  },
  "o1-pro": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_streaming": false
  },
  "o1-pro-2025-03-19": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_streaming": false
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
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "api_type": "responses",
    "supports_web_search": true,
    "latency_tier": "slow",
    "is_reasoning_model": true
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
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "api_type": "responses",
    "supports_web_search": true,
    "latency_tier": "slow",
    "is_reasoning_model": true
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
    "reasoning_effort": [["minimal", "low", "medium", "high"], "medium"],
    "supports_streaming": false,
    "api_type": "responses",
    "supports_web_search": true,
    "latency_tier": "slow",
    "is_reasoning_model": true
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
    "reasoning_effort": [["minimal", "low", "medium", "high"], "high"],
    "api_type": "responses",
    "supports_web_search": true,
    "latency_tier": "slow",
    "is_reasoning_model": true
  },
  "o3-mini": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": false,
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "api_type": "responses",
    "is_reasoning_model": true
  },
  "o3-mini-2025-01-31": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": false,
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "api_type": "responses",
    "is_reasoning_model": true
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
    "reasoning_effort": [["minimal", "low", "medium", "high"], "high"],
    "is_reasoning_model": true
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
    "reasoning_effort": [["minimal", "low", "medium", "high"], "high"],
    "is_reasoning_model": true
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
    "reasoning_effort": [["minimal", "low", "medium", "high"], "high"]
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
    "reasoning_effort": [["minimal", "low", "medium", "high"], "high"]
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
    "api_version": "2023-06-01",
    "max_output_tokens" : [[1, 32000], 32000],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "thinking_budget": {
      "min": 1024,
      "default": 10000,
      "max": null
    },
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_streaming": true,
    "supports_context_management": true
  },
  "claude-opus-4-20250514": {
    "context_window" : [1, 200000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [[1, 32000], 32000],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "thinking_budget": {
      "min": 1024,
      "default": 10000,
      "max": null
    },
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_streaming": true,
    "supports_context_management": true,
    "beta_flags": [
      "interleaved-thinking-2025-05-14",
      "pdfs-2024-09-25"
    ]
  },
  "claude-sonnet-4-20250514": {
    "context_window" : [1, 1000000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [[1, 64000], 64000],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "thinking_budget": {
      "min": 1024,
      "default": 10000,
      "max": null
    },
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_streaming": true,
    "supports_context_management": true,
    "beta_flags": [
      "interleaved-thinking-2025-05-14",
      "pdfs-2024-09-25"
    ]
  },
  "claude-sonnet-4-5-20250929": {
    "context_window" : [1, 1000000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [[1, 64000], 64000],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "thinking_budget": {
      "min": 1024,
      "default": 10000,
      "max": null
    },
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_streaming": true,
    "supports_context_management": true,
    "context_awareness": true,
    "beta_flags": [
      "interleaved-thinking-2025-05-14",
      "pdfs-2024-09-25"
    ]
  },
  "claude-3-7-sonnet-20250219": {
    "context_window" : [1, 200000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [[1, 64000], 64000],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "thinking_budget": {
      "min": 1024,
      "default": 10000,
      "max": null
    },
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_streaming": true,
    "beta_flags": [
      "interleaved-thinking-2025-05-14",
      "pdfs-2024-09-25"
    ]
  },
  "claude-3-5-sonnet-20240620": {
    "context_window" : [1, 200000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": false,
    "supports_web_search": true,
    "supports_streaming": true,
    "supports_pdf": true,
    "beta_flags": [
      "pdfs-2024-09-25"
    ],
    "deprecated": true
  },
  "claude-3-5-sonnet-20241022": {
    "context_window" : [1, 200000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": false,
    "supports_web_search": true,
    "supports_streaming": true,
    "supports_pdf": true,
    "beta_flags": [
      "pdfs-2024-09-25"
    ],
    "deprecated": true
  },
  "claude-3-5-haiku-20241022": {
    "context_window" : [1, 200000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "vision_capability": false,
    "supports_thinking": false,
    "supports_web_search": true,
    "supports_streaming": true,
    "supports_pdf": false,
    "deprecated": true
  },
  "claude-3-opus-20240229": {
    "context_window" : [1, 200000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [1, 4096],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": false,
    "supports_web_search": false,
    "supports_streaming": true,
    "supports_pdf": true,
    "beta_flags": [
      "pdfs-2024-09-25"
    ]
  },
  "claude-3-haiku-20240307": {
    "context_window" : [1, 200000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [1, 4096],
    "temperature": [[0.0, 1.0], 1.0],
    "top_p": [0.0, 1.0],
    "tool_capability": true,
    "vision_capability": false,
    "supports_streaming": true,
    "supports_pdf": false,
    "supports_thinking": false,
    "supports_web_search": false
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
    "vision_capability": true,
    "deprecated": false
  },
  "command-a-03-2025": {
    "context_window" : [1, 256000],
    "max_output_tokens" : [1, 8000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "deprecated": false
  },
  "command-a-translate-08-2025": {
    "context_window" : [1, 8992],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": false,
    "deprecated": false
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
  "command-a-reasoning-08-2025": {
    "context_window" : [1, 256000],
    "max_output_tokens" : [1, 32000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "supports_thinking": true,
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "reasoning_effort": [["disabled", "enabled"], "enabled"],
    "reasoning_model": true
  },
  "c4ai-aya-vision-8b": {
    "context_window" : [1, 8000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "vision_capability": true
  },
  "c4ai-aya-expanse-8b": {
    "context_window" : [1, 8000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0]
  },
  "c4ai-aya-expanse-32b": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.09], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
  },
  "command-r-08-2024": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "deprecated": false
  },
  "command-r-plus-08-2024": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "deprecated": false
  },
  "command-r7b-12-2024": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "deprecated": false
  },
  "command-r7b-arabic-02-2025": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "deprecated": false
  },
  // Gemini models
  "gemini-2.5-flash-lite-06-17": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "thinking_budget": {
      "min": 512,
      "max": 24576,
      "can_disable": true,
      "default_disabled": true,
      "presets": {
        "none": 0,
        "minimal": 0,
        "low": 512,
        "medium": 8000,
        "high": 20000
      }
    },
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true
  },
  "gemini-2.5-flash-lite": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "thinking_budget": {
      "min": 512,
      "max": 24576,
      "can_disable": true,
      "default_disabled": true,
      "presets": {
        "none": 0,
        "minimal": 0,
        "low": 512,
        "medium": 8000,
        "high": 20000
      }
    },
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true
  },
  "gemini-2.5-flash-lite-preview-09-2025": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "thinking_budget": {
      "min": 512,
      "max": 24576,
      "can_disable": true,
      "default_disabled": true,
      "presets": {
        "none": 0,
        "minimal": 0,
        "low": 512,
        "medium": 8000,
        "high": 20000
      }
    },
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true
  },
  "gemini-2.5-flash": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "thinking_budget": {
      "min": 128,
      "max": 20000,
      "can_disable": true,
      "default_disabled": true,
      "presets": {
        "none": 0,
        "minimal": 0,
        "low": 512,
        "medium": 8000,
        "high": 20000
      }
    },
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true
  },
  "gemini-2.5-flash-preview-09-2025": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "thinking_budget": {
      "min": 128,
      "max": 20000,
      "can_disable": true,
      "default_disabled": true,
      "presets": {
        "none": 0,
        "minimal": 0,
        "low": 512,
        "medium": 8000,
        "high": 20000
      }
    },
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true
  },
  "gemini-2.5-pro": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "thinking_budget": {
      "min": 128,
      "max": 32768,
      "can_disable": false,
      "presets": {
        "minimal": 128,
        "low": 5000,
        "medium": 20000,
        "high": 28000
      }
    },
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true
  },
  // Experimental models
  "gemini-2.5-pro-exp": {
    "context_window" : [1, 1000000],
    "max_output_tokens" : [1, 64000],
    "thinking_budget": {
      "min": 128,
      "max": 32768,
      "can_disable": false,
      "presets": {
        "minimal": 128,
        "low": 5000,
        "medium": 20000,
        "high": 28000
      }
    },
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true
  },
  "gemini-2.0-pro-exp-02-05": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf": true
  },
  "gemini-2.0-pro-exp": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf": true
  },
  "gemini-2.0-flash-thinking-exp": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "supports_web_search": true
  },
  "gemini-2.0-flash-thinking-exp-1219": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "supports_web_search": true
  },
  "gemini-2.0-flash-thinking-exp-01-21": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "supports_web_search": true
  },
  // Flash models
  "gemini-2.0-flash-exp": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true
  },
  "gemini-2.0-flash-001": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf": true
  },
  "gemini-2.0-flash": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true
  },
  "gemini-2.0-flash-lite-preview": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf": true
  },
  "gemini-2.0-flash-lite-preview-02-05": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf": true
  },
  "gemini-2.0-flash-lite": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf": true
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
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "supports_thinking": true
  },
  "magistral-small-2509": {
    "context_window" : [1, 40000],
    "max_output_tokens" : [1, 40000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "supports_thinking": true
  },
  "magistral-medium-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 128000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "supports_thinking": true,
    "vision_capability": true
  },
  "magistral-medium-2509": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 128000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "supports_thinking": true,
    "vision_capability": true
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
  "grok-4-fast-reasoning": {
    "context_window" : [1, 2000000],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "vision_capability": true,
    "websearch_capability": true,
    "supports_web_search": true,
    "supports_parallel_function_calling": true,
    "reasoning_effort": [["minimal", "low", "medium", "high"], "medium"],
    "is_reasoning_model": true
  },
  "grok-4-fast-non-reasoning": {
    "context_window" : [1, 2000000],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "vision_capability": true,
    "websearch_capability": true,
    "supports_web_search": true,
    "supports_parallel_function_calling": true
  },
  "grok-code-fast-1": {
    "context_window" : [1, 256000],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "reasoning_effort": [["low", "high"], "low"],
    "websearch_capability": false,
    "fallback_for_websearch": "grok-4-fast-reasoning",
    "supports_web_search": false,
    "supports_parallel_function_calling": true
  },
  "grok-2-vision-1212": {
    "context_window" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": false,
    "supports_parallel_function_calling": true,
    "supports_pdf": false
  },
  "grok-2-1212": {
    "context_window" : [1, 131072],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "supports_web_search": false,
    "supports_parallel_function_calling": true
  },
  "grok-3": {
    "context_window" : [1, 131072],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "supports_web_search": false,
    "supports_parallel_function_calling": true
  },
  "grok-3-mini": {
    "context_window" : [1, 131072],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "supports_web_search": false,
    "supports_parallel_function_calling": true
  },
  "grok-4-0709": {
    "context_window" : [1, 2000000],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "tool_capability": true,
    "vision_capability": true,
    "websearch_capability": true,
    "supports_web_search": true,
    "supports_parallel_function_calling": true
  },
  // Perplexity models
  "sonar-deep-research": {
    "context_window" : [1, 128000],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "low"],
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_pdf_upload": false
  },
  "sonar-reasoning-pro": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 8000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0],
    "vision_capability": true,
    "is_reasoning_model": true,
    "reasoning_effort": [["minimal", "low", "medium", "high"], "medium"],
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_pdf_upload": false
  },
  "sonar-reasoning": {
    "context_window" : [1, 128000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "medium"],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0],
    "vision_capability": true,
    "is_reasoning_model": true,
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_pdf_upload": false
  },
  "sonar-pro": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [1, 8000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0],
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_pdf_upload": false
  },
  "sonar": {
    "context_window" : [1, 128000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[0.0, 2.0], 1.0],
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_pdf_upload": false
  },
  // DeepSeek models
  "deepseek-chat": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0], 
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "reasoning_content": ["disabled", "enabled"]
  },
  "deepseek-reasoner": {
    "context_window" : [1, 64000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0], 
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "reasoning_content": ["disabled", "enabled"],
    "tool_capability": true
  }
}

// Expose modelSpec globally for browser environment
if (typeof window !== 'undefined') {
  window.modelSpec = modelSpec;
}

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = modelSpec;
}
