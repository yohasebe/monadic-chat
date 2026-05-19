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
    "supports_file_inputs": true,
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
    "supports_file_inputs": true,
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
    "supports_file_inputs": true,
    "skip_in_progress_events": true
  },
  "gpt-5.3-codex": {
    "context_window": [1, 400000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["low", "medium", "high", "xhigh"], "low"],
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
    "supports_web_search": true,
    "supports_pdf": false,
    "skip_in_progress_events": true
  },
  "gpt-5.2-codex": {
    "context_window": [1, 400000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["low", "medium", "high", "xhigh"], "low"],
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
    "supports_web_search": true,
    "supports_pdf": false,
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
    "supports_file_inputs": true,
    "skip_in_progress_events": true
  },
  // GPT-5.5 (new generation, 1M context, shares gpt-5.4 architecture)
  "gpt-5.5": {
    "context_window": [1, 1050000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "low", "medium", "high", "xhigh"], "none"],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["low", "medium", "high"], "medium"],
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "supports_file_inputs": true,
    "skip_in_progress_events": true
  },
  // GPT-5.4 Thinking (frontier model, 1M context, computer use)
  "gpt-5.4": {
    "context_window": [1, 1050000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "low", "medium", "high", "xhigh"], "none"],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["low", "medium", "high"], "medium"],
    "supports_structured_output": true,
    "api_type": "responses",
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "supports_file_inputs": true,
    "skip_in_progress_events": true
  },
  // GPT-5.4 Mini (cost-efficient, 400K context, tool search, computer use, compaction)
  "gpt-5.4-mini": {
    "context_window": [1, 400000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "low", "medium", "high", "xhigh"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["low", "medium", "high"], "medium"],
    "api_type": "responses",
    "supports_web_search": true,
    "supports_pdf_upload": true,
    "supports_file_inputs": true,
    "skip_in_progress_events": true
  },
  // GPT-5.4 Nano (high-volume simple tasks, 400K context, compaction)
  "gpt-5.4-nano": {
    "context_window": [1, 400000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "low", "medium", "high", "xhigh"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "verbosity": [["low", "medium", "high"], "medium"],
    "api_type": "responses",
    "supports_web_search": true,
    "skip_in_progress_events": true
  },
  // Gemini 3 image preview (image generation only) — deprecated
  "gemini-3-pro-image-preview": {
    "context_window": [1, 32000],
    "max_output_tokens": [1, 8192],
    "vision_capability": true,
    "image_generation": true,
    "supports_web_search": false,
    "skip_in_progress_events": true,
    "deprecated": true,
    "sunset_date": "2026-06-30",
    "successor": "gemini-3.1-flash-image-preview"
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
    "supports_pdf_upload": true,
    "supports_file_inputs": true,
    "deprecated": true,
    "sunset_date": "2026-06-30",
    "successor": "gpt-5.4-mini"
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
    "supports_pdf_upload": true,
    "supports_file_inputs": true,
    "deprecated": true,
    "sunset_date": "2026-06-30",
    "successor": "gpt-5.4-nano"
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
  // Anthropic models
  "claude-opus-4-7": {
    "context_window" : [1, 1000000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [[1, 128000], 128000],
    "reasoning_effort": [["low", "medium", "high", "xhigh", "max"], "high"],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "supports_adaptive_thinking": true,
    "thinking_budget": {
      "min": 1024,
      "default": 10000,
      "max": null
    },
    "rejects_sampling_params": true,
    "thinking_display_default_omitted": true,
    "supports_web_search": true,
    "supports_pdf": true,
    "supports_streaming": true,
    "supports_context_management": true,
    "structured_output": true,
    "structured_output_mode": "json_schema",
    "beta_flags": []
  },
  "claude-opus-4-6": {
    "context_window" : [1, 1000000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [[1, 128000], 128000],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "supports_adaptive_thinking": true,
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
    "beta_flags": []
  },
  "claude-sonnet-4-6": {
    "context_window" : [1, 1000000],
    "api_version": "2023-06-01",
    "max_output_tokens" : [[1, 64000], 64000],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "supports_adaptive_thinking": true,
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
    "beta_flags": []
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
    "structured_output": true,
    "structured_output_mode": "json_schema",

    "beta_flags": [
      "interleaved-thinking-2025-05-14"
    ],
    "sunset_date": "2026-06-15",
    "successor": "claude-opus-4-7"
  },
  "claude-opus-4-5-20251101": {
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
    "beta_flags": [
      "interleaved-thinking-2025-05-14"
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

    "beta_flags": [
      "interleaved-thinking-2025-05-14"
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

    "beta_flags": [
      "interleaved-thinking-2025-05-14"
    ],
    "sunset_date": "2026-06-15",
    "successor": "claude-sonnet-4-6"
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
    "beta_flags": []
  },
  "claude-sonnet-4-5-20250929": {
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
    "context_awareness": true,
    "structured_output": true,
    "structured_output_mode": "json_schema",
    "beta_flags": [
      "interleaved-thinking-2025-05-14"
    ]
  },
  // Cohere models
  "command-a-03-2025": {
    "context_window" : [1, 256000],
    "max_output_tokens" : [1, 8000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "vision_capability": false
  },
  "command-a-vision-07-2025": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 8000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
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
  // Gemini models
  // Gemini 3.5 Flash (GA, sustained frontier for agentic + coding tasks).
  // Stable alias of the gemini-3-flash-preview line.
  "gemini-3.5-flash": {
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
  "gemini-3.1-pro-preview": {
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
  "gemini-3.1-pro-preview-customtools": {
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
    "tool_capability": true,
    "vision_capability": true,
    "supports_web_search": true,
    "supports_pdf": true,
    "ui_hidden": true
  },
  "gemini-3.1-flash-lite-preview": {
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
    "supports_pdf": true,
    "deprecated": true,
    "sunset_date": "2026-05-25",
    "successor": "gemini-3.5-flash"
  },
  "gemini-3.1-flash-image-preview": {
    "context_window": [131072],
    "max_output_tokens": [1, 32768],
    "vision_capability": true,
    "image_generation": true,
    "supports_web_search": true,
    "skip_in_progress_events": true
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
    "supports_pdf": true,
    "deprecated": true,
    "sunset_date": "2026-07-22",
    "successor": "gemini-3.1-flash-lite-preview"
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
    "supports_pdf": true,
    "deprecated": true,
    "sunset_date": "2026-06-17",
    "successor": "gemini-3-flash-preview"
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
    "supports_pdf": true,
    "deprecated": true,
    "sunset_date": "2026-06-17",
    "successor": "gemini-3.1-pro-preview"
  },
  // Mistral models
  // devstral models (agentic code — replaces codestral for tool-use workflows)
  "devstral-latest": {
    "max_output_tokens" : [1, 262000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  // codestral models (code completion)
  "codestral-latest": {
    "max_output_tokens" : [1, 256000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true
  },
  "mistral-large-latest": {
    "max_output_tokens" : [1, 262000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  // Mistral Medium 3.5: frontier-class multimodal, agentic + coding,
  // 256k context, function calling, structured outputs, adjustable
  // reasoning_effort. supports_thinking gates mistral_helper's
  // reasoning_effort routing — see lib/monadic/adapters/vendors/mistral_helper.rb.
  "mistral-medium-3-5": {
    "max_output_tokens" : [1, 262000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_structured_output": true,
    "supports_thinking": true
  },
  // Mistral Small 4 (mistral-small-2603): hybrid instruct+reasoning+coding,
  // 256k context, 119B params with 6.5B active, cost-efficient.
  "mistral-small-2603": {
    "max_output_tokens" : [1, 262000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_structured_output": true,
    "supports_thinking": true
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
  "mistral-small-latest": {
    "max_output_tokens" : [1, 262000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true
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
    "max_output_tokens" : [1, 262000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true
  },
  "ministral-14b-latest": {
    "max_output_tokens" : [1, 262000],
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
  "grok-4.20-0309-reasoning": {
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
  "grok-4.20-0309-non-reasoning": {
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
  "grok-4.20-multi-agent-0309": {
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
  // Unified flagship. Sampling parameters are partially restricted:
  // temperature and top_p are accepted, but presence_penalty /
  // frequency_penalty are rejected, so they are intentionally absent.
  // Context window is 1M, smaller than the 4.20 family's 2M.
  // reasoning_effort: low / medium / high (xAI 2026-05 announcement).
  "grok-4.3": {
    "context_window" : [1, 1000000],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
    "websearch_capability": true,
    "supports_web_search": true,
    "supports_parallel_function_calling": true,
    "structured_output": true
  },
  // DeepSeek models
  // V4 series: unified models with thinking/non-thinking mode toggle
  "deepseek-v4-flash": {
    "context_window" : [1, 1000000],
    "max_output_tokens" : [1, 384000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "reasoning_content": ["disabled", "enabled"],
    "reasoning_effort": ["high", "max"]
  },
  "deepseek-v4-pro": {
    "context_window" : [1, 1000000],
    "max_output_tokens" : [1, 384000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "reasoning_content": ["disabled", "enabled"],
    "reasoning_effort": ["high", "max"]
  },
  // Legacy models (sunset 2026-07-24, successor: deepseek-v4-flash)
  "deepseek-chat": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "reasoning_content": ["disabled", "enabled"],
    "deprecated": true,
    "sunset_date": "2026-07-24",
    "successor": "deepseek-v4-flash"
  },
  "deepseek-reasoner": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 64000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "reasoning_content": ["disabled", "enabled"],
    "tool_capability": true,
    "deprecated": true,
    "sunset_date": "2026-07-24",
    "successor": "deepseek-v4-flash"
  },
  // Ollama models (local inference)
  // NOTE: Ollama model capabilities are normally fetched dynamically via
  // /api/ollama/models (see model_loader.js). This static entry exists only
  // as a safety net — it ensures the recommended model's image upload and
  // thinking panel still work if Ollama was unreachable at page load.
  // Dynamic entries override this when Ollama is available.
  "qwen3-vl:8b-thinking": {
    "context_window": [1, 262144],
    "max_output_tokens": [1, 32768],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true
  },

  // -------------------------------------------------------------------------
  // TTS model metadata (Expressive Speech SSOT)
  //
  // `tts_family` matches the canonical family keys used by
  // TtsTextProcessors.family_for (Ruby) and TtsTagSanitizer.familyFor (JS).
  // `tts_instructions_capability: true` means the model accepts the
  // out-of-band `instructions` parameter (currently OpenAI gpt-4o-mini-tts
  // only). `tts_voices` is the list the UI uses when it gates the voice
  // dropdown by the active TTS model.
  // -------------------------------------------------------------------------
  "gpt-4o-mini-tts-2025-12-15": {
    "tts_capability": true,
    "tts_family": "openai-instruction",
    "tts_instructions_capability": true,
    "tts_voices": ["alloy", "ash", "ballad", "coral", "echo", "fable",
                   "onyx", "nova", "sage", "shimmer", "verse", "marin", "cedar"],
    "tts_default_voice": "coral",
    "tts_audio_formats": ["mp3", "opus", "aac", "flac", "wav", "pcm"],
    "tts_streaming": true
  },
  "tts-1-hd": {
    "tts_capability": true,
    "tts_family": "openai",
    "tts_instructions_capability": false,
    "tts_voices": ["alloy", "ash", "coral", "echo", "fable", "onyx",
                   "nova", "sage", "shimmer"],
    "tts_default_voice": "alloy",
    "tts_audio_formats": ["mp3", "opus", "aac", "flac", "wav", "pcm"],
    "tts_streaming": true
  },
  "tts-1": {
    "tts_capability": true,
    "tts_family": "openai",
    "tts_instructions_capability": false,
    "tts_voices": ["alloy", "ash", "coral", "echo", "fable", "onyx",
                   "nova", "sage", "shimmer"],
    "tts_default_voice": "alloy",
    "tts_audio_formats": ["mp3", "opus", "aac", "flac", "wav", "pcm"],
    "tts_streaming": true
  },
  "grok-tts": {
    "tts_capability": true,
    "tts_family": "xai",
    "tts_instructions_capability": false
  },
  "gemini-3.1-flash-tts-preview": {
    "tts_capability": true,
    "tts_family": "gemini",
    "tts_instructions_capability": true
  },
  "gemini-2.5-flash-preview-tts": {
    "tts_capability": true,
    "tts_family": "gemini",
    "tts_instructions_capability": true
  },
  "gemini-2.5-pro-preview-tts": {
    "tts_capability": true,
    "tts_family": "gemini",
    "tts_instructions_capability": true
  },
  "voxtral-mini-tts-2603": {
    "tts_capability": true,
    "tts_family": "mistral",
    "tts_instructions_capability": false
  },
  "eleven_v3": {
    "tts_capability": true,
    "tts_family": "elevenlabs-v3",
    "tts_instructions_capability": false
  },
  "eleven_multilingual_v2": {
    "tts_capability": true,
    "tts_family": "elevenlabs",
    "tts_instructions_capability": false
  },
  "eleven_flash_v2_5": {
    "tts_capability": true,
    "tts_family": "elevenlabs",
    "tts_instructions_capability": false
  },

  // -------------------------------------------------------------------------
  // STT model metadata (Speech-to-Text capability SSOT)
  //
  // Entries only exist for models that need a capability flag beyond
  // "appears in providerDefaults.audio_transcription". Today that means
  // streaming-capable models — gated by `supports_realtime_streaming`.
  // The frontend gate (`recording.js`) and the Ruby accessor
  // (`ModelSpec.supports_realtime_streaming?`) both read this flag.
  // -------------------------------------------------------------------------
  "gpt-realtime-whisper": {
    "stt_capability": true,
    "supports_realtime_streaming": true
  }
}

/**
 * Provider Defaults (SSOT)
 *
 * Purpose: Defines which models to use by default for each provider × category.
 * This is separate from modelSpec above, which defines model *capabilities*.
 *
 * Structure: { provider: { category: [model1, model2, ...] } }
 *   - First element = primary default (used when no model is explicitly specified)
 *   - List order = priority (fallback order)
 *   - Categories: chat, code, vision, audio_transcription, image, video, tts, embedding
 *
 * How it's used:
 *   - MDSL apps without explicit `model` → providerDefaults[provider].chat[0]
 *   - Ruby agents → ModelSpec.default_chat_model("openai"), .default_code_model, etc.
 *   - Frontend UI → pre-selects the default model in dropdowns
 *
 * When adding a new model: add its definition to modelSpec above, then update
 * providerDefaults here if it should become a default.
 */
const providerDefaults = {
  "openai": {
    "chat": ["gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.5", "gpt-5.2", "gpt-5.1"],
    "code": ["gpt-5.3-codex", "gpt-5.2-codex", "gpt-5.4-mini"],
    "vision": ["gpt-5.4-mini"],
    "audio_transcription": ["gpt-4o-mini-transcribe-2025-12-15"],
    "image": ["gpt-image-2", "gpt-image-1.5", "chatgpt-image-latest"],
    "tts": ["gpt-4o-mini-tts-2025-12-15", "tts-1-hd", "tts-1"]
  },
  "anthropic": {
    "chat": ["claude-sonnet-4-6", "claude-haiku-4-5-20251001"],
    "code": ["claude-sonnet-4-6"],
    "vision": ["claude-haiku-4-5-20251001"]
  },
  "gemini": {
    "chat": ["gemini-3.5-flash", "gemini-3.1-pro-preview"],
    "vision": ["gemini-3.5-flash"],
    "audio_transcription": ["gemini-3.5-flash"],
    "image": ["gemini-3.1-flash-image-preview", "imagen-4.0-fast-generate-001", "imagen-4.0-generate-001", "imagen-4.0-ultra-generate-001"],
    "video": ["veo-3.1-fast-generate-preview", "veo-3.1-generate-preview"],
    "tts": ["gemini-3.1-flash-tts-preview", "gemini-2.5-flash-preview-tts", "gemini-2.5-pro-preview-tts"]
  },
  "cohere": {
    "chat": ["command-a-03-2025", "command-a-vision-07-2025", "command-a-reasoning-08-2025"],
    "audio_transcription": ["cohere-transcribe-03-2026"]
  },
  "mistral": {
    "chat": ["mistral-medium-3-5", "mistral-large-latest"],
    "code": ["devstral-latest", "mistral-small-2603"],
    "vision": ["mistral-small-2603"],
    "tts": ["voxtral-mini-tts-2603"],
    "audio_transcription": ["voxtral-mini-transcribe-2507"]
  },
  "xai": {
    "chat": ["grok-4.20-0309-non-reasoning", "grok-4.3", "grok-4.20-0309-reasoning", "grok-4.20-multi-agent-0309"],
    "code": ["grok-4.3"],
    "vision": ["grok-4.3"],
    "image": ["grok-imagine-image"],
    "video": ["grok-imagine-video"],
    "tts": ["grok-tts"],
    "audio_transcription": ["xai-stt"]
  },
  "deepseek": {
    "chat": ["deepseek-v4-flash", "deepseek-v4-pro"]
  },
  "ollama": {
    "chat": ["gemma4:e4b", "qwen3-vl:8b-thinking"]
  },
  "elevenlabs": {
    "tts": ["eleven_v3", "eleven_multilingual_v2", "eleven_flash_v2_5"],
    "audio_transcription": ["scribe_v2", "scribe_v1"]
  }
};

// Expose modelSpec globally for browser environment
if (typeof window !== 'undefined') {
  window.modelSpec = modelSpec;
  window.providerDefaults = providerDefaults;
}

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = modelSpec;
  // Non-enumerable so Object.keys(module.exports) still returns only model names
  Object.defineProperty(module.exports, 'providerDefaults', {
    value: providerDefaults,
    enumerable: false,
    configurable: true
  });
}
