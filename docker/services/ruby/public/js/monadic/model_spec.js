const modelSpec = {
  // gpt-5 models
  // gpt-4.1 models
  // gpt-4o models
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
    "supports_pdf_upload": false,
    "deprecated": false
  },
  // reasoning models
  // O3 series models
  // O4 series models
  // Other OpenAI models
  // Anthropic models
  // Cohere models
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
  "gemini-2.5-flash-lite-preview-06-17": {
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
  "gemini-2.5-flash-preview-05-20": {
    "context_window" : [1048576],
    "max_output_tokens" : [1, 65536],
    "reasoning_effort": [["minimal", "low", "medium", "high"], "low"],
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
  "gemini-2.5-pro-preview-06-05": {
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
  "gemini-2.5-pro-preview-05-06": {
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
  "gemini-2.5-pro-preview-03-25": {
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
  "gemini-2.5-pro-exp-03-25": {
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
  // Mistral models
  // codestral models
  // pixtral models
  // Non-latest pixtral and mistral models
  // ministral models
  // open models
  // xAI models
  "grok-1": {
    "context_window" : [1, 131072],
    "max_output_tokens" : [1, 8192],
    "temperature": [[0.0, 1.0], 0.5],
    "top_p": [[0.0, 1.0], 0.9],
    "tool_capability": true,
    "supports_web_search": true,
    "supports_pdf": false,
    "deprecated": false
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
    "reasoning_content": ["disabled", "enabled"],
    "deprecated": false
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
