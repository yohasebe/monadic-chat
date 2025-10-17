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
        uiLanguage: "UI Language",
        syntaxHighlighting: "Syntax Highlighting Theme",
        darkThemes: "──Dark Themes──",
        lightThemes: "──Light Themes──",
        speechToText: "STT_MODEL (Speech-to-Text)",
        ttsDictPath: "TTS Dictionary File Path",
        selectFile: "Select File",
        autoTtsRealtimeMode: "Auto TTS Realtime Mode",
        autoTtsRealtimeModeDesc: "When enabled, generates TTS during text streaming. When disabled (default), generates TTS after streaming completes.",
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
        unsavedTitle: "Unsaved Changes",
        unsavedMessage: "You have unsaved changes. Save before closing?",
        saveAndClose: "Save and Close",
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
        uiLanguage: "UI言語",
        syntaxHighlighting: "構文ハイライト テーマ",
        darkThemes: "──ダークテーマ──",
        lightThemes: "──ライトテーマ──",
        speechToText: "STT_MODEL (音声認識)",
        ttsDictPath: "TTS辞書ファイルパス",
        selectFile: "ファイル選択",
        autoTtsRealtimeMode: "自動TTSリアルタイムモード",
        autoTtsRealtimeModeDesc: "有効にすると、テキストのストリーミング中にTTSを生成します。無効（デフォルト）の場合、ストリーミング完了後にTTSを生成します。",
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
        unsavedTitle: "未保存の変更",
        unsavedMessage: "保存していない変更があります。閉じる前に保存しますか？",
        saveAndClose: "保存して閉じる",
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
        uiLanguage: "界面语言",
        syntaxHighlighting: "语法高亮主题",
        darkThemes: "──深色主题──",
        lightThemes: "──浅色主题──",
        speechToText: "STT_MODEL (语音转文本)",
        ttsDictPath: "TTS字典文件路径",
        selectFile: "选择文件",
        autoTtsRealtimeMode: "自动TTS实时模式",
        autoTtsRealtimeModeDesc: "启用时，在文本流式传输期间生成TTS。禁用时（默认），在流式传输完成后生成TTS。",
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
        unsavedTitle: "未保存的更改",
        unsavedMessage: "您有未保存的更改。是否在关闭前保存？",
        saveAndClose: "保存并关闭",
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
        uiLanguage: "UI 언어",
        syntaxHighlighting: "구문 강조 테마",
        darkThemes: "──다크 테마──",
        lightThemes: "──라이트 테마──",
        speechToText: "STT_MODEL (음성-텍스트 변환)",
        ttsDictPath: "TTS 사전 파일 경로",
        selectFile: "파일 선택",
        autoTtsRealtimeMode: "자동 TTS 실시간 모드",
        autoTtsRealtimeModeDesc: "활성화하면 텍스트 스트리밍 중에 TTS를 생성합니다. 비활성화(기본값)하면 스트리밍 완료 후 TTS를 생성합니다.",
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
        unsavedTitle: "저장되지 않은 변경 사항",
        unsavedMessage: "저장하지 않은 변경 사항이 있습니다. 닫기 전에 저장하시겠습니까?",
        saveAndClose: "저장하고 닫기",
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
        uiLanguage: "Idioma de UI",
        syntaxHighlighting: "Tema de Resaltado de Sintaxis",
        darkThemes: "──Temas Oscuros──",
        lightThemes: "──Temas Claros──",
        speechToText: "STT_MODEL (Voz a Texto)",
        ttsDictPath: "Ruta del Archivo de Diccionario TTS",
        selectFile: "Seleccionar Archivo",
        autoTtsRealtimeMode: "Modo TTS Automático en Tiempo Real",
        autoTtsRealtimeModeDesc: "Cuando está habilitado, genera TTS durante la transmisión de texto. Cuando está deshabilitado (predeterminado), genera TTS después de que se complete la transmisión.",
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
        unsavedTitle: "Cambios sin guardar",
        unsavedMessage: "Tienes cambios sin guardar. ¿Guardar antes de cerrar?",
        saveAndClose: "Guardar y cerrar",
        modeChanged: "Modo Cambiado",
        modeChangeMessage: "La configuración del modo ha cambiado. La aplicación debe reiniciarse para que este cambio surta efecto. Por favor, cierre y reinicie Monadic Chat manualmente.",
        ok: "OK"
      }
    }
  },
  fr: {
    settings: {
      title: "Paramètres",
      loading: "Chargement des paramètres...",
      categories: {
        apiKeys: "Clés API",
        modelSettings: "Paramètres du Modèle",
        displayUI: "Affichage et Interface",
        voiceAudio: "Voix et Audio",
        systemSettings: "Paramètres Système"
      },
      labels: {
        uiLanguage: "Langue de l'UI",
        syntaxHighlighting: "Thème de Coloration Syntaxique",
        darkThemes: "──Thèmes Sombres──",
        lightThemes: "──Thèmes Clairs──",
        speechToText: "STT_MODEL (Reconnaissance Vocale)",
        ttsDictPath: "Chemin du Fichier Dictionnaire TTS",
        selectFile: "Sélectionner Fichier",
        autoTtsRealtimeMode: "Mode TTS Automatique en Temps Réel",
        autoTtsRealtimeModeDesc: "Lorsqu'activé, génère le TTS pendant la diffusion du texte. Lorsque désactivé (par défaut), génère le TTS après la fin de la diffusion.",
        applicationMode: "Mode Application",
        standaloneMode: "Autonome (Par défaut)",
        serverMode: "Mode Serveur",
        browserMode: "Mode Navigateur",
        internalBrowser: "Navigateur Interne",
        externalBrowser: "Navigateur Externe",
        extraLogging: "Journalisation Supplémentaire",
        enableMcpServer: "Activer le Serveur MCP",
        mcpServerPort: "Port du Serveur MCP"
      },
      buttons: {
        showApiKeys: "Afficher les Clés API",
        hideApiKeys: "Masquer les Clés API",
        save: "Enregistrer",
        close: "Fermer"
      },
      messages: {
        settingsSaved: "Paramètres enregistrés",
        unsavedTitle: "Modifications non enregistrées",
        unsavedMessage: "Vous avez des modifications non enregistrées. Enregistrer avant de fermer ?",
        saveAndClose: "Enregistrer et fermer",
        modeChanged: "Mode Modifié",
        modeChangeMessage: "Le paramètre de mode a été modifié. L'application doit être redémarrée pour que ce changement prenne effet. Veuillez fermer et redémarrer Monadic Chat manuellement.",
        ok: "OK"
      }
    }
  },
  de: {
    settings: {
      title: "Einstellungen",
      loading: "Einstellungen werden geladen...",
      categories: {
        apiKeys: "API-Schlüssel",
        modelSettings: "Modelleinstellungen",
        displayUI: "Anzeige und Benutzeroberfläche",
        voiceAudio: "Sprache und Audio",
        systemSettings: "Systemeinstellungen"
      },
      labels: {
        uiLanguage: "UI-Sprache",
        syntaxHighlighting: "Syntaxhervorhebungsthema",
        darkThemes: "──Dunkle Themen──",
        lightThemes: "──Helle Themen──",
        speechToText: "STT_MODEL (Spracherkennung)",
        ttsDictPath: "TTS-Wörterbuchdateipfad",
        selectFile: "Datei auswählen",
        autoTtsRealtimeMode: "Automatischer TTS-Echtzeitmodus",
        autoTtsRealtimeModeDesc: "Wenn aktiviert, wird TTS während des Text-Streamings generiert. Wenn deaktiviert (Standard), wird TTS nach Abschluss des Streamings generiert.",
        applicationMode: "Anwendungsmodus",
        standaloneMode: "Eigenständig (Standard)",
        serverMode: "Server-Modus",
        browserMode: "Browser-Modus",
        internalBrowser: "Interner Browser",
        externalBrowser: "Externer Browser",
        extraLogging: "Zusätzliche Protokollierung",
        enableMcpServer: "MCP-Server aktivieren",
        mcpServerPort: "MCP-Server-Port"
      },
      buttons: {
        showApiKeys: "API-Schlüssel anzeigen",
        hideApiKeys: "API-Schlüssel verbergen",
        save: "Speichern",
        close: "Schließen"
      },
      messages: {
        settingsSaved: "Einstellungen gespeichert",
        unsavedTitle: "Nicht gespeicherte Änderungen",
        unsavedMessage: "Sie haben nicht gespeicherte Änderungen. Vor dem Schließen speichern?",
        saveAndClose: "Speichern und schließen",
        modeChanged: "Modus geändert",
        modeChangeMessage: "Die Moduseinstellung wurde geändert. Die Anwendung muss neu gestartet werden, damit diese Änderung wirksam wird. Bitte schließen und starten Sie Monadic Chat manuell neu.",
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
