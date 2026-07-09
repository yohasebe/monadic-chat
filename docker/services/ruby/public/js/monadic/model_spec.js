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
  // -------------------------------------------------------------------------
  // GPT-5.6 family (Sol / Terra / Luna, released 2026-07-09). All three:
  // 1.05M context, 128K output, text+image in / text out, Responses API,
  // knowledge cutoff 2026-02-16. Positioning per OpenAI: Sol = flagship for
  // complex reasoning/agentic coding ($5/$30 per 1M), Terra = default tier
  // balancing intelligence and cost ($2.50/$15), Luna = cost-optimized
  // ($1/$6). The reasoning enumeration was verified against the live API
  // 2026-07-10: the error enum lists none…xhigh, and "max" (the announced Max
  // mode) is additionally accepted and echoed by all three models; "ultra" is
  // rejected (ChatGPT-side only), so it is intentionally absent here.
  // -------------------------------------------------------------------------
  "gpt-5.6-sol": {
    "context_window": [1, 1050000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "minimal", "low", "medium", "high", "xhigh", "max"], "none"],
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
  "gpt-5.6-terra": {
    "context_window": [1, 1050000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "minimal", "low", "medium", "high", "xhigh", "max"], "none"],
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
  "gpt-5.6-luna": {
    "context_window": [1, 1050000],
    "max_output_tokens": [1, 128000],
    "reasoning_effort": [["none", "minimal", "low", "medium", "high", "xhigh", "max"], "none"],
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
  // Gemini 3 Pro Image (Nano Banana Pro) — image generation only, GA 2026-05-28
  "gemini-3-pro-image": {
    "context_window": [1, 32000],
    "max_output_tokens": [1, 8192],
    "vision_capability": true,
    "image_generation": true,
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
  // Fable 5 is Anthropic's top tier (above Opus). Same API contract as Opus
  // 4.7/4.8 — adaptive thinking only, rejects sampling params, effort
  // [low..max]. The one Fable-5-specific breaking change (an explicit
  // thinking {type:"disabled"} returns 400) needs no handling here: the Claude
  // helper omits the thinking param entirely when reasoning is off rather than
  // sending "disabled". Premium-priced ($10/$50 per MTok, 2x Opus) so it stays
  // out of providerDefaults — opt-in via the model dropdown only.
  "claude-fable-5": {
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
    "beta_flags": [],
    "unavailable_fallback": "claude-opus-4-8"
  },
  "claude-opus-4-8": {
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
  "claude-sonnet-5": {
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
  // Command A+ (Cohere flagship, MoE 25B active / 218B total).
  // Unifies vision + reasoning + tool use; 128k context but 64k output.
  // Older command-a-* entries remain for long-context (256k) workloads.
  "command-a-plus-05-2026": {
    "context_window" : [1, 128000],
    "max_output_tokens" : [1, 64000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.01, 0.99], 0.75],
    "frequency_penalty": [[0.0, 1.0], 0.0],
    "presence_penalty": [[0.0, 1.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_thinking": true,
    "supports_structured_output": true,
    "reasoning_effort": [["disabled", "enabled"], "enabled"],
    "native_multiturn_reasoning": true
  },
  // North Mini Code (Cohere's first agentic-coding model; MoE 30B total / 3B
  // active, Apache 2.0). Reasoning-native and verified to handle the native
  // Cohere v2 multi-turn tool flow without the single-text flattening that
  // command-a-reasoning needs (`native_multiturn_reasoning`). Context shown per
  // Cohere's published 256k spec.
  "north-mini-code-1-0": {
    "context_window" : [1, 256000],
    "max_output_tokens" : [1, 64000],
    "tool_capability": true,
    "supports_thinking": true,
    "reasoning_model": true,
    "reasoning_effort": [["disabled", "enabled"], "enabled"],
    "supports_structured_output": true,
    "native_multiturn_reasoning": true
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
    "supports_pdf": true,
    "deprecated": true,
    "sunset_date": "2026-06-25",
    "successor": "gemini-3.5-flash"
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
  "gemini-3.1-flash-lite": {
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
  // Gemini 3.1 Flash Image (Nano Banana 2) — image generation + video-to-image, GA 2026-05-28
  "gemini-3.1-flash-image": {
    "context_window": [131072],
    "max_output_tokens": [1, 32768],
    "vision_capability": true,
    "image_generation": true,
    "supports_video_to_image": true,
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
    "successor": "gemini-3.1-flash-lite"
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
    "successor": "gemini-3.5-flash"
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
  // 256k context, function calling, structured outputs. The Mistral API
  // accepts only "none" or "high" for reasoning_effort on this family —
  // "low"/"medium" return 400 — so pin the enum here so the UI never
  // offers an unsupported value.
  "mistral-medium-3-5": {
    "max_output_tokens" : [1, 262000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_structured_output": true,
    "supports_thinking": true,
    "reasoning_effort": [["none", "high"], "none"]
  },
  // Mistral Small 4 (mistral-small-2603): hybrid instruct+reasoning+coding,
  // 256k context, 119B params with 6.5B active, cost-efficient.
  // Same reasoning_effort enum constraint as Medium 3.5.
  "mistral-small-2603": {
    "max_output_tokens" : [1, 262000],
    "temperature": [[0.0, 1.0], 0.3],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "supports_structured_output": true,
    "supports_thinking": true,
    "reasoning_effort": [["none", "high"], "none"]
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
  // grok-4.5 (Grok 4.5) — xAI's V9-architecture frontier model (2026-07).
  // 500K context, text+image in / text out. Reasoning model (emits
  // reasoning_content) with selectable reasoning_effort (low/medium/high),
  // tool calling, web search, and structured output. Pricing ~$2 in / $6 out /
  // ~$0.50 cached per 1M (long-context tier ~doubles above the 200K threshold).
  // presence_penalty / frequency_penalty omitted to match the grok-4.3
  // sampling-restriction posture. Verified against the live xAI API 2026-07-09.
  "grok-4.5": {
    "context_window" : [1, 500000],
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
  // grok-build-0.1 (Grok Build 0.1) — xAI's fast agentic-coding model
  // (public beta). Rebrand/successor of grok-code-fast-1 (xAI lists
  // grok-code-fast-1 as an alias). 256k context, text+image in / text out,
  // tool calling + structured output + reasoning. Same pricing as grok-4.3
  // ($1/$2/$0.20 cached). presence_penalty / frequency_penalty are omitted
  // to match the grok-4.3 sampling-restriction posture.
  "grok-build-0.1": {
    "context_window" : [1, 256000],
    "max_output_tokens" : [1, 32768],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "reasoning_effort": [["low", "medium", "high"], "low"],
    "tool_capability": true,
    "vision_capability": true,
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
    "tts_instructions_capability": false,
    // Authoritative built-in voice roster from xAI GET /v1/tts/voices
    // (all natively multilingual). `eve` is the xAI default. Keep in sync
    // with the grok-tts-voice options in views/index.erb.
    "tts_voices": ["altair", "ara", "atlas", "carina", "castor", "celeste",
      "cosmo", "eve", "helios", "helix", "iris", "kepler", "leo", "lumen",
      "luna", "lux", "naksh", "orion", "perseus", "rex", "rigel", "sal",
      "sirius", "ursa", "zagan", "zenith"]
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
    "chat": ["gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.6-luna", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.5", "gpt-5.2", "gpt-5.1"],
    "code": ["gpt-5.3-codex", "gpt-5.6-sol", "gpt-5.2-codex", "gpt-5.4-mini"],
    "vision": ["gpt-5.6-luna", "gpt-5.4-mini"],
    "audio_transcription": ["gpt-4o-mini-transcribe-2025-12-15"],
    "image": ["gpt-image-2"],
    "tts": ["gpt-4o-mini-tts-2025-12-15", "tts-1-hd", "tts-1"]
  },
  "anthropic": {
    "chat": ["claude-sonnet-5", "claude-haiku-4-5-20251001"],
    "code": ["claude-sonnet-5"],
    "vision": ["claude-haiku-4-5-20251001"]
  },
  "gemini": {
    "chat": ["gemini-3.5-flash", "gemini-3.1-pro-preview"],
    "vision": ["gemini-3.5-flash"],
    "audio_transcription": ["gemini-3.5-flash"],
    "image": ["gemini-3.1-flash-image", "imagen-4.0-fast-generate-001", "imagen-4.0-generate-001", "imagen-4.0-ultra-generate-001"],
    "video": ["veo-3.1-fast-generate-preview", "veo-3.1-generate-preview"],
    "music": ["lyria-3-pro-preview", "lyria-3-clip-preview"],
    "tts": ["gemini-3.1-flash-tts-preview", "gemini-2.5-flash-preview-tts", "gemini-2.5-pro-preview-tts"]
  },
  "cohere": {
    "chat": ["command-a-plus-05-2026", "command-a-03-2025", "command-a-vision-07-2025", "command-a-reasoning-08-2025"],
    "vision": ["command-a-plus-05-2026"],
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
    "chat": ["grok-4.5", "grok-4.20-0309-non-reasoning", "grok-4.3", "grok-4.20-0309-reasoning", "grok-4.20-multi-agent-0309"],
    "code": ["grok-build-0.1", "grok-4.5", "grok-4.3"],
    "vision": ["grok-4.5", "grok-4.3"],
    "image": ["grok-imagine-image"],
    // text-to-video default. Image-to-video is routed to grok-imagine-video-1.5
    // in scripts/generators/video_generator_grok.rb (i2v-only, native audio,
    // higher quality; v1.5 rejects text-only requests).
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
    "audio_transcription": ["scribe_v2"]
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
