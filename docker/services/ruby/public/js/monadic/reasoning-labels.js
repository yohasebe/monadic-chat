/**
 * Provider-specific labels and descriptions for reasoning/thinking features
 */

class ReasoningLabels {
  static getLabel(provider, model) {
    const spec = window.modelSpec && window.modelSpec[model];
    if (!spec) return this.getDefaultLabel();
    
    // Get language from UI
    const lang = window.webUIi18n && window.webUIi18n.currentLanguage || 'en';
    console.log(`[ReasoningLabels] Getting label for provider=${provider}, model=${model}, lang=${lang}`);
    
    const labels = {
      'en': {
        'OpenAI': "Reasoning Effort",
        'Anthropic': "Thinking Level",
        'Google': "Thinking Mode",
        'xAI': "Reasoning Effort",
        'DeepSeek': "Reasoning Mode",
        'Perplexity': "Research Depth",
        'default': "Reasoning Effort"
      },
      'ja': {
        'OpenAI': "推論強度",
        'Anthropic': "思考レベル",
        'Google': "思考モード",
        'xAI': "推論強度",
        'DeepSeek': "推論モード",
        'Perplexity': "探索深度",
        'default': "推論強度"
      },
      'zh': {
        'OpenAI': "推理强度",
        'Anthropic': "思考级别",
        'Google': "思考模式",
        'xAI': "推理强度",
        'DeepSeek': "推理模式",
        'Perplexity': "搜索深度",
        'default': "推理强度"
      },
      'ko': {
        'OpenAI': "추론 강도",
        'Anthropic': "사고 수준",
        'Google': "사고 모드",
        'xAI': "추론 강도",
        'DeepSeek': "추론 모드",
        'Perplexity': "탐색 깊이",
        'default': "추론 강도"
      },
      'es': {
        'OpenAI': "Esfuerzo de Razonamiento",
        'Anthropic': "Nivel de Pensamiento",
        'Google': "Modo de Pensamiento",
        'xAI': "Esfuerzo de Razonamiento",
        'DeepSeek': "Modo de Razonamiento",
        'Perplexity': "Profundidad de Búsqueda",
        'default': "Esfuerzo de Razonamiento"
      },
      'fr': {
        'OpenAI': "Effort de Raisonnement",
        'Anthropic': "Niveau de Réflexion",
        'Google': "Mode de Réflexion",
        'xAI': "Effort de Raisonnement",
        'DeepSeek': "Mode de Raisonnement",
        'Perplexity': "Profondeur de Recherche",
        'default': "Effort de Raisonnement"
      },
      'de': {
        'OpenAI': "Denkaufwand",
        'Anthropic': "Denkniveau",
        'Google': "Denkmodus",
        'xAI': "Denkaufwand",
        'DeepSeek': "Denkmodus",
        'Perplexity': "Suchtiefe",
        'default': "Denkaufwand"
      }
    };
    
    const langLabels = labels[lang] || labels['en'];
    
    // Check if model supports specific reasoning type
    let labelKey = 'default';
    if (provider === 'Anthropic' && spec.supports_thinking === true) {
      labelKey = 'Anthropic';
    } else if (provider === 'Google' && spec.thinking_budget) {
      labelKey = 'Google';
    } else if (provider === 'DeepSeek' && spec.reasoning_content) {
      labelKey = 'DeepSeek';
    } else if (provider === 'Perplexity' && spec.reasoning_effort) {
      labelKey = 'Perplexity';
    } else if (provider === 'xAI' && spec.reasoning_effort) {
      labelKey = 'xAI';
    } else if (provider === 'OpenAI' && spec.reasoning_effort) {
      labelKey = 'OpenAI';
    }
    
    return langLabels[labelKey] || langLabels['default'];
  }
  
  static getDefaultLabel() {
    const lang = window.webUIi18n && window.webUIi18n.currentLanguage || 'en';
    const defaults = {
      'en': "Reasoning Effort",
      'ja': "推論強度",
      'zh': "推理强度",
      'ko': "추론 강도",
      'es': "Esfuerzo de Razonamiento",
      'fr': "Effort de Raisonnement",
      'de': "Denkaufwand"
    };
    return defaults[lang] || defaults['en'];
  }
  
  static getDescription(provider, model) {
    const spec = window.modelSpec && window.modelSpec[model];
    if (!spec) return null;
    
    // Get language from UI
    const lang = window.webUIi18n && window.webUIi18n.currentLanguage || 'en';
    
    const descriptions = {
      'en': {
        'OpenAI': "Controls computational depth for reasoning",
        'Anthropic': "Controls how deeply Claude thinks through problems",
        'Google': "Balances response quality with processing time",
        'xAI': "Adjusts Grok's reasoning depth",
        'DeepSeek': "Enable or disable step-by-step reasoning",
        'Perplexity': "Controls search and analysis depth"
      },
      'ja': {
        'OpenAI': "推論の計算深度を制御",
        'Anthropic': "Claudeの思考深度を制御",
        'Google': "品質と処理時間のバランス",
        'xAI': "Grokの推論深度を調整",
        'DeepSeek': "段階的推論の有効/無効",
        'Perplexity': "検索と分析の深度を制御"
      },
      'zh': {
        'OpenAI': "控制推理计算深度",
        'Anthropic': "控制Claude思考深度",
        'Google': "平衡质量与处理时间",
        'xAI': "调整Grok推理深度",
        'DeepSeek': "启用/禁用分步推理",
        'Perplexity': "控制搜索和分析深度"
      },
      'ko': {
        'OpenAI': "추론 계산 깊이 제어",
        'Anthropic': "Claude 사고 깊이 제어",
        'Google': "품질과 처리 시간 균형",
        'xAI': "Grok 추론 깊이 조정",
        'DeepSeek': "단계별 추론 활성/비활성",
        'Perplexity': "검색 및 분석 깊이 제어"
      },
      'es': {
        'OpenAI': "Controla la profundidad computacional",
        'Anthropic': "Controla la profundidad de pensamiento",
        'Google': "Equilibra calidad con tiempo",
        'xAI': "Ajusta la profundidad de razonamiento",
        'DeepSeek': "Habilitar/deshabilitar razonamiento",
        'Perplexity': "Controla profundidad de búsqueda"
      },
      'fr': {
        'OpenAI': "Contrôle la profondeur de calcul",
        'Anthropic': "Contrôle la profondeur de réflexion",
        'Google': "Équilibre qualité et temps",
        'xAI': "Ajuste la profondeur de raisonnement",
        'DeepSeek': "Activer/désactiver le raisonnement",
        'Perplexity': "Contrôle la profondeur de recherche"
      },
      'de': {
        'OpenAI': "Steuert die Rechenleistung",
        'Anthropic': "Steuert Claudes Denktiefe",
        'Google': "Balance zwischen Qualität und Zeit",
        'xAI': "Passt Groks Denktiefe an",
        'DeepSeek': "Schrittweises Denken ein/aus",
        'Perplexity': "Steuert Such- und Analysetiefe"
      }
    };
    
    // Check if model supports reasoning
    const hasReasoning = 
      (provider === 'OpenAI' && spec.reasoning_effort) ||
      (provider === 'Anthropic' && spec.supports_thinking === true) ||
      (provider === 'Google' && spec.thinking_budget) ||
      (provider === 'xAI' && spec.reasoning_effort) ||
      (provider === 'DeepSeek' && spec.reasoning_content) ||
      (provider === 'Perplexity' && spec.reasoning_effort);
    
    if (!hasReasoning) return null;
    
    const langDescriptions = descriptions[lang] || descriptions['en'];
    return langDescriptions[provider] || null;
  }
  
  static getOptionLabel(provider, option) {
    // Get language from UI
    const lang = window.webUIi18n && window.webUIi18n.currentLanguage || 'en';
    
    // Provider-specific option labels with translations
    const labels = {
      'en': {
        'default': {
          'minimal': 'Minimal',
          'low': 'Low',
          'medium': 'Medium',
          'high': 'High'
        },
        'Anthropic': {
          'minimal': 'Minimal (Fast)',
          'low': 'Low (Efficient)',
          'medium': 'Medium (Balanced)',
          'high': 'High (Thorough)'
        },
        'Google': {
          'minimal': 'Minimal',
          'low': 'Low (Efficient)',
          'medium': 'Medium (Balanced)',
          'high': 'High (Quality)'
        },
        'xAI': {
          'low': 'Low (Fast)',
          'medium': 'Medium (Balanced)',
          'high': 'High (Detailed)'
        },
        'DeepSeek': {
          'minimal': 'Off',
          'medium': 'On'
        },
        'Perplexity': {
          'minimal': 'Quick Search',
          'low': 'Standard Search',
          'medium': 'Deep Research',
          'high': 'Comprehensive Analysis'
        }
      },
      'ja': {
        'default': {
          'minimal': '最小',
          'low': '低',
          'medium': '中',
          'high': '高'
        },
        'Anthropic': {
          'minimal': '最小（高速）',
          'low': '低（効率的）',
          'medium': '中（バランス）',
          'high': '高（徹底的）'
        },
        'Google': {
          'minimal': '最小',
          'low': '低（効率的）',
          'medium': '中（バランス）',
          'high': '高（品質）'
        },
        'xAI': {
          'low': '低（高速）',
          'medium': '中（バランス）',
          'high': '高（詳細）'
        },
        'DeepSeek': {
          'minimal': 'オフ',
          'medium': 'オン'
        },
        'Perplexity': {
          'minimal': 'クイック検索',
          'low': '標準検索',
          'medium': '詳細検索',
          'high': '包括的分析'
        }
      },
      'zh': {
        'default': {
          'minimal': '最小',
          'low': '低',
          'medium': '中',
          'high': '高'
        },
        'Anthropic': {
          'minimal': '最小（快速）',
          'low': '低（高效）',
          'medium': '中（平衡）',
          'high': '高（彻底）'
        },
        'Google': {
          'minimal': '最小',
          'low': '低（高效）',
          'medium': '中（平衡）',
          'high': '高（质量）'
        },
        'xAI': {
          'low': '低（快速）',
          'medium': '中（平衡）',
          'high': '高（详细）'
        },
        'DeepSeek': {
          'minimal': '关闭',
          'medium': '开启'
        },
        'Perplexity': {
          'minimal': '快速搜索',
          'low': '标准搜索',
          'medium': '深度搜索',
          'high': '综合分析'
        }
      },
      'ko': {
        'default': {
          'minimal': '최소',
          'low': '낮음',
          'medium': '중간',
          'high': '높음'
        },
        'DeepSeek': {
          'minimal': '끄기',
          'medium': '켜기'
        }
      },
      'es': {
        'default': {
          'minimal': 'Mínimo',
          'low': 'Bajo',
          'medium': 'Medio',
          'high': 'Alto'
        },
        'DeepSeek': {
          'minimal': 'Desactivado',
          'medium': 'Activado'
        }
      },
      'fr': {
        'default': {
          'minimal': 'Minimal',
          'low': 'Faible',
          'medium': 'Moyen',
          'high': 'Élevé'
        },
        'DeepSeek': {
          'minimal': 'Désactivé',
          'medium': 'Activé'
        }
      },
      'de': {
        'default': {
          'minimal': 'Minimal',
          'low': 'Niedrig',
          'medium': 'Mittel',
          'high': 'Hoch'
        },
        'DeepSeek': {
          'minimal': 'Aus',
          'medium': 'Ein'
        }
      }
    };
    
    const langLabels = labels[lang] || labels['en'];
    
    // Try provider-specific label first, then fall back to default
    if (langLabels[provider] && langLabels[provider][option]) {
      return langLabels[provider][option];
    } else if (langLabels['default'] && langLabels['default'][option]) {
      return langLabels['default'][option];
    }
    
    // If no translation found, use English default
    if (labels['en'][provider] && labels['en'][provider][option]) {
      return labels['en'][provider][option];
    } else if (labels['en']['default'] && labels['en']['default'][option]) {
      return labels['en']['default'][option];
    }
    
    // Final fallback
    return option.charAt(0).toUpperCase() + option.slice(1);
  }
  
  /**
   * Update UI labels dynamically
   */
  static updateUILabels(provider, model) {
    // Update main label
    const label = this.getLabel(provider, model);
    const labelElement = document.querySelector('label[for="reasoning-effort"]');
    if (labelElement) {
      labelElement.textContent = label;
    }
    
    // Remove any existing description to prevent layout issues
    const container = document.getElementById('reasoning-effort').parentElement;
    let descElement = container.querySelector('.reasoning-description');
    if (descElement) {
      descElement.remove();
    }
    
    // Update option labels
    const select = document.getElementById('reasoning-effort');
    if (select) {
      const options = select.querySelectorAll('option');
      options.forEach(option => {
        const value = option.value;
        const customLabel = this.getOptionLabel(provider, value);
        option.textContent = customLabel;
      });
    }
  }
}

// Make available globally
window.ReasoningLabels = ReasoningLabels;