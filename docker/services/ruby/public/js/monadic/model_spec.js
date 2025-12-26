const modelSpec = {
  // gpt-5 models
  "gpt-5": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "minimal"],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["low", "medium", "high"], "medium"],
    "api_type": "responses",
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true,
    "feature_constraints": {
      "reasoning_effort": {
        "incompatible_with": {
          "web_search": ["minimal"]
        }
      }
    }
  },
  "gpt-5-mini": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["low", "medium", "high"], "medium"],
    "api_type": "responses",
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
  },
  "gpt-5-nano": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["low", "medium", "high"], "medium"],
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
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_image_generation": true,
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
  "gpt-5-chat-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["medium"], "medium"],
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_image_generation": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
  },
  // gpt-5.1 models
  "gpt-5.1": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["none", "low", "medium", "high"], "none"],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["low", "medium", "high"], "medium"],
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
  },
  "gpt-5.1-chat-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "reasoning_effort": [["medium"], "medium"],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["medium"], "medium"],
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_image_generation": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
  },
  "gpt-5.1-codex": {
    "context_window": [1, 400000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "low", "medium", "high"], "none"],
    "tool_capability": true,
    "vision_capability": true,
    "api_type": "responses",
    "supports_streaming": true,
    "supports_temperature": false,
    "supports_top_p": false,
    "supports_presence_penalty": false,
    "supports_frequency_penalty": false,
    "supports_structured_output": true,
    "is_agent_model": true,
    "agent_type": "coding",
    "adaptive_reasoning": true,
    "supports_web_search": false,
    "supports_pdf": false,
    "skip_in_progress_events": true
  },
  "gpt-5.1-codex-mini": {
    "context_window": [1, 400000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "low", "medium"], "none"],
    "tool_capability": true,
    "vision_capability": true,
    "api_type": "responses",
    "supports_streaming": true,
    "supports_temperature": false,
    "supports_top_p": false,
    "supports_presence_penalty": false,
    "supports_frequency_penalty": false,
    "supports_structured_output": true,
    "is_agent_model": true,
    "agent_type": "coding",
    "adaptive_reasoning": true,
    "supports_web_search": false,
    "supports_pdf": false,
    "skip_in_progress_events": true
  },
  "gpt-5.1-codex-max": {
    "context_window": [1, 400000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "medium", "high", "xhigh"], "none"],
    "tool_capability": true,
    "vision_capability": true,
    "api_type": "responses",
    "supports_streaming": true,
    "supports_temperature": false,
    "supports_top_p": false,
    "supports_presence_penalty": false,
    "supports_frequency_penalty": false,
    "supports_structured_output": true,
    "is_agent_model": true,
    "agent_type": "coding",
    "adaptive_reasoning": true,
    "supports_web_search": false,
    "supports_pdf": false,
    "skip_in_progress_events": true
  },
  // gpt-5.2 models (GPT-5.2 Thinking)
  "gpt-5.2": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    "reasoning_effort": [["none", "low", "medium", "high", "xhigh"], "none"],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["low", "medium", "high"], "medium"],
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
  },
  // GPT-5.2 Instant (fast, everyday tasks)
  "gpt-5.2-chat-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 16384],
    "reasoning_effort": [["medium"], "medium"],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["medium"], "medium"],
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_image_generation": true,
    "supports_pdf_upload": true,
    "skip_in_progress_events": true
  },
  // GPT-5.2 Pro (maximum accuracy)
  "gpt-5.2-pro": {
    "context_window" : [1, 400000],
    "max_output_tokens" : [1, 128000],
    // reasoning_effort: not specified - use OpenAI's default (likely "high")
    "tool_capability": true,
    "vision_capability": false,
    "supports_structured_output": false,
    "api_type": "responses",
    "supports_web_search": false,
    "supports_pdf_upload": false,
    "skip_in_progress_events": true,
    "requires_confirmation": true
  },
  // Gemini 3 image preview (image generation only)
  "gemini-3-pro-image-preview": {
    "context_window": [1, 32000],
    "max_output_tokens": [1, 8192],
    "vision_capability": true,
    "image_generation": true,
    "api_type": "responses",
    "supports_web_search": false,
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
  "o1": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "tool_capability": false,
    "vision_capability": false
  },
  "o1-pro": {
    "context_window" : [1, 200000],
    "max_output_tokens" : [25000, 100000],
    "reasoning_effort": [["none", "low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_streaming": false,
    "requires_confirmation": true
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
  "o3-pro": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["none", "low", "medium", "high"], "medium"],
    "supports_streaming": false,
    "api_type": "responses",
    "supports_web_search": true,
    "latency_tier": "slow",
    "is_reasoning_model": true,
    "requires_confirmation": true
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
  "o3-deep-research": {
    "context_window": [1, 200000],
    "max_output_tokens": [1, 100000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["none", "low", "medium", "high"], "high"],
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
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "api_type": "responses",
    "supports_web_search": true
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
    "reasoning_effort": [["none", "low", "medium", "high"], "high"]
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
  // Anthropic models
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
    "structured_output": true,
    "structured_output_mode": "json_schema",
    "structured_output_beta": "structured-outputs-2025-11-13",
    "beta_flags": [
      "interleaved-thinking-2025-05-14",
      "pdfs-2024-09-25"
    ]
  },
  "claude-opus-4-5-20251101": {
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
    "structured_output": true,
    "structured_output_mode": "json_schema",
    "structured_output_beta": "structured-outputs-2025-11-13",
    "beta_flags": [
      "interleaved-thinking-2025-05-14",
      "pdfs-2024-09-25"
    ]
  },
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
    "supports_context_management": true,
    "structured_output": true,
    "structured_output_mode": "json_schema",
    "structured_output_beta": "structured-outputs-2025-11-13",
    "beta_flags": [
      "interleaved-thinking-2025-05-14",
      "pdfs-2024-09-25"
    ]
  },
  "claude-sonnet-4-20250514": {
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
    "supports_context_management": true,
    "structured_output": true,
    "structured_output_mode": "json_schema",
    "structured_output_beta": "structured-outputs-2025-11-13",
    "beta_flags": [
      "interleaved-thinking-2025-05-14",
      "pdfs-2024-09-25"
    ]
  },
  "claude-haiku-4-5-20251001": {
    "context_window" : [1, 200000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [[1, 8192], 8192],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": false,
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_streaming": true,
    "beta_flags": [
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
    "structured_output": true,
    "structured_output_mode": "json_schema",
    "structured_output_beta": "structured-outputs-2025-11-13",
    "beta_flags": [
      "interleaved-thinking-2025-05-14",
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
  "c4ai-aya-vision-32b": {
    "context_window" : [1, 16000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
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
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "vision_capability": true
  },
  "c4ai-aya-expanse-8b": {
    "context_window" : [1, 8000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": false
  },
  "c4ai-aya-expanse-32b": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 4000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": false
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
  "gemini-3-flash-preview": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "thinking_budget": {
      "min": 128,
      "max": 24576,
      "can_disable": true,
      "default_disabled": true,
      "presets": {
        "none": 0,
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
  "gemini-3-pro-preview": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["low", "high"], "low"],
    "supports_thinking": true,
    "supports_thinking_level": true,
    "thinking_level": [["low", "high"], "low"],
    "thinking_budget": {
      "min": 1024,
      "max": 32768,
      "can_disable": false,
      "presets": {
        "low": 8000,
        "high": 20000
      }
    },
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
        "none": 128,
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
        "none": 128,
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
  "gemini-2.0-pro-exp": {
    "context_window" : [1, 1048576],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 0.95],
    "tool_capability": true,
    "vision_capability": true,
    "supports_pdf": true
  },
  // Flash models
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
    "tool_capability": true,
    "vision_capability": true
  },
  "mistral-vibe-cli-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 128000],
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
  // magistral models (reasoning models)
  "magistral-small-latest": {
    "context_window" : [1, 40000],
    "max_output_tokens" : [1, 40000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true
  },
  "magistral-medium-latest": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 128000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true
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
    "tool_capability": true,
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
  // Mistral Labs experimental models
  "labs-mistral-small-creative": {
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 0.8],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": false
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
    "tool_capability": true,
    "vision_capability": true
  },
  "ministral-8b-latest": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "ministral-14b-latest": {
    "max_output_tokens" : [1, 131000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
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
    "supports_parallel_function_calling": true
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
  "grok-4-1-fast-reasoning": {
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
  "grok-4-1-fast-non-reasoning": {
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
    "fallback_for_websearch": "grok-4-1-fast-reasoning",
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
    "reasoning_effort": [["low", "high"], "low"],
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
    "reasoning_effort": [["low", "high"], "low"],
    "supports_web_search": true,
    "supports_parallel_function_calling": true
  },
  // Perplexity models
  "sonar-deep-research": {
    "context_window" : [1, 128000],
    "reasoning_effort": [["none", "low", "medium", "high"], "low"],
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
    "reasoning_effort": [["none", "low", "medium", "high"], "medium"],
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_pdf_upload": false
  },
  "sonar-reasoning": {
    "context_window" : [1, 128000],
    "temperature": [[0.0, 1.99], 0.9],
    "top_p": [[0.0, 1.0], 0.9],
    "reasoning_effort": [["none", "low", "medium", "high"], "medium"],
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
