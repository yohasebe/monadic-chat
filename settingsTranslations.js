// Settings UI Translations
const settingsTranslations = {
  en: {
    settings: {
      title: "Settings",
      loading: "Loading settings...",
      categories: {
        apiKeys: "API Keys",
        modelSettings: "Model Settings",
        displayUI: "Display & UI",
        voiceAudio: "Voice & Audio",
        systemSettings: "System Settings"
      },
      labels: {
        interfaceLanguage: "Interface Language",
        syntaxHighlighting: "Syntax Highlighting Theme",
        darkThemes: "──Dark Themes──",
        lightThemes: "──Light Themes──",
        speechToText: "STT_MODEL (Speech-to-Text)",
        ttsDictPath: "TTS Dictionary File Path",
        selectFile: "Select File",
        applicationMode: "Application Mode",
        standaloneMode: "Standalone (Default)",
        serverMode: "Server Mode",
        browserMode: "Browser Mode",
        internalBrowser: "Internal Browser",
        externalBrowser: "External Browser",
        extraLogging: "Extra Logging",
        enableMcpServer: "Enable MCP Server",
        mcpServerPort: "MCP Server Port"
      },
      buttons: {
        showApiKeys: "Show API Keys",
        hideApiKeys: "Hide API Keys",
        save: "Save",
        close: "Close"
      },
      messages: {
        settingsSaved: "Settings saved",
        modeChanged: "Mode Changed",
        modeChangeMessage: "Mode setting has been changed. The application needs to be restarted for this change to take effect. Please close and restart Monadic Chat manually.",
        ok: "OK"
      }
    }
  },
  ja: {
    settings: {
      title: "設定",
      loading: "設定を読み込み中...",
      categories: {
        apiKeys: "APIキー",
        modelSettings: "モデル設定",
        displayUI: "表示・UI",
        voiceAudio: "音声・オーディオ",
        systemSettings: "システム設定"
      },
      labels: {
        interfaceLanguage: "インターフェース言語",
        syntaxHighlighting: "構文ハイライト テーマ",
        darkThemes: "──ダークテーマ──",
        lightThemes: "──ライトテーマ──",
        speechToText: "STT_MODEL (音声認識)",
        ttsDictPath: "TTS辞書ファイルパス",
        selectFile: "ファイル選択",
        applicationMode: "アプリケーションモード",
        standaloneMode: "スタンドアロン (デフォルト)",
        serverMode: "サーバーモード",
        browserMode: "ブラウザモード",
        internalBrowser: "内部ブラウザ",
        externalBrowser: "外部ブラウザ",
        extraLogging: "追加ログ",
        enableMcpServer: "MCPサーバーを有効化",
        mcpServerPort: "MCPサーバーポート"
      },
      buttons: {
        showApiKeys: "APIキーを表示",
        hideApiKeys: "APIキーを隠す",
        save: "保存",
        close: "閉じる"
      },
      messages: {
        settingsSaved: "設定を保存しました",
        modeChanged: "モード変更",
        modeChangeMessage: "モード設定が変更されました。この変更を有効にするにはアプリケーションの再起動が必要です。Monadic Chatを手動で閉じて再起動してください。",
        ok: "OK"
      }
    }
  },
  zh: {
    settings: {
      title: "设置",
      loading: "加载设置中...",
      categories: {
        apiKeys: "API密钥",
        modelSettings: "模型设置",
        displayUI: "显示和UI",
        voiceAudio: "语音和音频",
        systemSettings: "系统设置"
      },
      labels: {
        interfaceLanguage: "界面语言",
        syntaxHighlighting: "语法高亮主题",
        darkThemes: "──深色主题──",
        lightThemes: "──浅色主题──",
        speechToText: "STT_MODEL (语音转文本)",
        ttsDictPath: "TTS字典文件路径",
        selectFile: "选择文件",
        applicationMode: "应用模式",
        standaloneMode: "单机模式（默认）",
        serverMode: "服务器模式",
        browserMode: "浏览器模式",
        internalBrowser: "内部浏览器",
        externalBrowser: "外部浏览器",
        extraLogging: "额外日志",
        enableMcpServer: "启用MCP服务器",
        mcpServerPort: "MCP服务器端口"
      },
      buttons: {
        showApiKeys: "显示API密钥",
        hideApiKeys: "隐藏API密钥",
        save: "保存",
        close: "关闭"
      },
      messages: {
        settingsSaved: "设置已保存",
        modeChanged: "模式已更改",
        modeChangeMessage: "模式设置已更改。此更改需要重新启动应用程序才能生效。请手动关闭并重启Monadic Chat。",
        ok: "确定"
      }
    }
  },
  ko: {
    settings: {
      title: "설정",
      loading: "설정 로드 중...",
      categories: {
        apiKeys: "API 키",
        modelSettings: "모델 설정",
        displayUI: "디스플레이 및 UI",
        voiceAudio: "음성 및 오디오",
        systemSettings: "시스템 설정"
      },
      labels: {
        interfaceLanguage: "인터페이스 언어",
        syntaxHighlighting: "구문 강조 테마",
        darkThemes: "──다크 테마──",
        lightThemes: "──라이트 테마──",
        speechToText: "STT_MODEL (음성-텍스트 변환)",
        ttsDictPath: "TTS 사전 파일 경로",
        selectFile: "파일 선택",
        applicationMode: "애플리케이션 모드",
        standaloneMode: "독립형 (기본값)",
        serverMode: "서버 모드",
        browserMode: "브라우저 모드",
        internalBrowser: "내부 브라우저",
        externalBrowser: "외부 브라우저",
        extraLogging: "추가 로깅",
        enableMcpServer: "MCP 서버 활성화",
        mcpServerPort: "MCP 서버 포트"
      },
      buttons: {
        showApiKeys: "API 키 표시",
        hideApiKeys: "API 키 숨기기",
        save: "저장",
        close: "닫기"
      },
      messages: {
        settingsSaved: "설정이 저장되었습니다",
        modeChanged: "모드 변경됨",
        modeChangeMessage: "모드 설정이 변경되었습니다. 이 변경 사항을 적용하려면 애플리케이션을 다시 시작해야 합니다. Monadic Chat를 수동으로 닫고 다시 시작하세요.",
        ok: "확인"
      }
    }
  },
  es: {
    settings: {
      title: "Configuración",
      loading: "Cargando configuración...",
      categories: {
        apiKeys: "Claves API",
        modelSettings: "Configuración del Modelo",
        displayUI: "Pantalla y UI",
        voiceAudio: "Voz y Audio",
        systemSettings: "Configuración del Sistema"
      },
      labels: {
        interfaceLanguage: "Idioma de Interfaz",
        syntaxHighlighting: "Tema de Resaltado de Sintaxis",
        darkThemes: "──Temas Oscuros──",
        lightThemes: "──Temas Claros──",
        speechToText: "STT_MODEL (Voz a Texto)",
        ttsDictPath: "Ruta del Archivo de Diccionario TTS",
        selectFile: "Seleccionar Archivo",
        applicationMode: "Modo de Aplicación",
        standaloneMode: "Independiente (Predeterminado)",
        serverMode: "Modo Servidor",
        browserMode: "Modo de Navegador",
        internalBrowser: "Navegador Interno",
        externalBrowser: "Navegador Externo",
        extraLogging: "Registro Adicional",
        enableMcpServer: "Habilitar Servidor MCP",
        mcpServerPort: "Puerto del Servidor MCP"
      },
      buttons: {
        showApiKeys: "Mostrar Claves API",
        hideApiKeys: "Ocultar Claves API",
        save: "Guardar",
        close: "Cerrar"
      },
      messages: {
        settingsSaved: "Configuración guardada",
        modeChanged: "Modo Cambiado",
        modeChangeMessage: "La configuración del modo ha cambiado. La aplicación debe reiniciarse para que este cambio surta efecto. Por favor, cierre y reinicie Monadic Chat manualmente.",
        ok: "OK"
      }
    }
  }
};

// Settings i18n helper class
class SettingsI18n {
  constructor() {
    this.currentLanguage = 'en';
    this.translations = settingsTranslations;
  }

  setLanguage(language) {
    if (this.translations[language]) {
      this.currentLanguage = language;
      this.updateUIText();
      return true;
    }
    console.warn(`Language ${language} not found, using English`);
    this.currentLanguage = 'en';
    return false;
  }

  t(key) {
    const keys = key.split('.');
    let value = this.translations[this.currentLanguage];
    let fallback = this.translations['en'];
    
    for (const k of keys) {
      value = value?.[k];
      fallback = fallback?.[k];
      
      if (!value && !fallback) {
        return key;
      }
    }
    
    return value || fallback || key;
  }

  updateUIText() {
    // Update elements with data-i18n attribute
    document.querySelectorAll('[data-i18n]').forEach(element => {
      const key = element.getAttribute('data-i18n');
      const translation = this.t(key);
      
      if (element.tagName === 'OPTION' && element.disabled) {
        // Skip disabled options (separators)
        element.textContent = translation;
      } else if (element.tagName === 'LABEL') {
        element.childNodes.forEach(node => {
          if (node.nodeType === Node.TEXT_NODE) {
            node.textContent = translation;
          }
        });
      } else if (element.tagName === 'BUTTON') {
        // Preserve icons in buttons
        const icon = element.querySelector('i');
        if (icon) {
          const iconHTML = icon.outerHTML;
          element.innerHTML = iconHTML + translation;
        } else {
          element.textContent = translation;
        }
      } else {
        // For h1, h2 and other elements, preserve icons
        const icon = element.querySelector('i');
        if (icon) {
          const iconHTML = icon.outerHTML;
          element.innerHTML = iconHTML + ' ' + translation;
        } else {
          element.textContent = translation;
        }
      }
    });
  }
}

// Create global instance
const settingsI18n = new SettingsI18n();

// Function to get cookie value
function getSettingsCookie(name) {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) return parts.pop().split(';').shift();
  return null;
}

// Initialize with saved language preference
document.addEventListener('DOMContentLoaded', () => {
  // Try to get language from settings or cookie
  const savedLanguage = getSettingsCookie('interface-language') || 
                       document.getElementById('interface-language')?.value || 
                       'en';
  if (savedLanguage && savedLanguage !== 'en') {
    settingsI18n.setLanguage(savedLanguage);
  }
});