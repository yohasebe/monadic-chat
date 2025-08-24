// Web UI Translations
const webUITranslations = {
  en: {
    ui: {
      start: "Start",
      stop: "Stop",
      restart: "Restart",
      rebuild: "Rebuild",
      update: "Update",
      send: "Send",
      clear: "Clear",
      voice: "Voice",
      settings: "Settings",
      version: "Version",
      conversationLanguage: "Conversation Language",
      currentBaseApp: "Current Base App",
      selectApp: "Select App",
      searchApps: "Search apps...",
      availableApps: "Available Apps",
      appCategories: {
        general: "General",
        specialized: "Specialized",
        tools: "Tools"
      },
      messages: {
        starting: "Starting Docker containers...",
        stopping: "Stopping Docker containers...",
        restarting: "Restarting Docker containers...",
        rebuilding: "Rebuilding Docker containers...",
        updating: "Updating Docker containers...",
        ready: "Ready",
        error: "Error",
        connecting: "Connecting..."
      }
    }
  },
  ja: {
    ui: {
      start: "開始",
      stop: "停止",
      restart: "再起動",
      rebuild: "再構築",
      update: "更新",
      send: "送信",
      clear: "クリア",
      voice: "音声",
      settings: "設定",
      version: "バージョン",
      conversationLanguage: "会話言語",
      currentBaseApp: "現在のアプリ",
      selectApp: "アプリを選択",
      searchApps: "アプリを検索...",
      availableApps: "利用可能なアプリ",
      appCategories: {
        general: "一般",
        specialized: "専門",
        tools: "ツール"
      },
      messages: {
        starting: "Dockerコンテナを起動しています...",
        stopping: "Dockerコンテナを停止しています...",
        restarting: "Dockerコンテナを再起動しています...",
        rebuilding: "Dockerコンテナを再構築しています...",
        updating: "Dockerコンテナを更新しています...",
        ready: "準備完了",
        error: "エラー",
        connecting: "接続中..."
      }
    }
  },
  zh: {
    ui: {
      start: "启动",
      stop: "停止",
      restart: "重启",
      rebuild: "重建",
      update: "更新",
      send: "发送",
      clear: "清除",
      voice: "语音",
      settings: "设置",
      version: "版本",
      conversationLanguage: "对话语言",
      currentBaseApp: "当前应用",
      selectApp: "选择应用",
      searchApps: "搜索应用...",
      availableApps: "可用应用",
      appCategories: {
        general: "通用",
        specialized: "专业",
        tools: "工具"
      },
      messages: {
        starting: "正在启动Docker容器...",
        stopping: "正在停止Docker容器...",
        restarting: "正在重启Docker容器...",
        rebuilding: "正在重建Docker容器...",
        updating: "正在更新Docker容器...",
        ready: "就绪",
        error: "错误",
        connecting: "连接中..."
      }
    }
  },
  ko: {
    ui: {
      start: "시작",
      stop: "중지",
      restart: "재시작",
      rebuild: "재구축",
      update: "업데이트",
      send: "전송",
      clear: "지우기",
      voice: "음성",
      settings: "설정",
      version: "버전",
      conversationLanguage: "대화 언어",
      currentBaseApp: "현재 앱",
      selectApp: "앱 선택",
      searchApps: "앱 검색...",
      availableApps: "사용 가능한 앱",
      appCategories: {
        general: "일반",
        specialized: "전문",
        tools: "도구"
      },
      messages: {
        starting: "Docker 컨테이너를 시작하는 중...",
        stopping: "Docker 컨테이너를 중지하는 중...",
        restarting: "Docker 컨테이너를 재시작하는 중...",
        rebuilding: "Docker 컨테이너를 재구축하는 중...",
        updating: "Docker 컨테이너를 업데이트하는 중...",
        ready: "준비 완료",
        error: "오류",
        connecting: "연결 중..."
      }
    }
  },
  es: {
    ui: {
      start: "Iniciar",
      stop: "Detener",
      restart: "Reiniciar",
      rebuild: "Reconstruir",
      update: "Actualizar",
      send: "Enviar",
      clear: "Limpiar",
      voice: "Voz",
      settings: "Configuración",
      version: "Versión",
      conversationLanguage: "Idioma de Conversación",
      currentBaseApp: "Aplicación Actual",
      selectApp: "Seleccionar App",
      searchApps: "Buscar apps...",
      availableApps: "Apps Disponibles",
      appCategories: {
        general: "General",
        specialized: "Especializado",
        tools: "Herramientas"
      },
      messages: {
        starting: "Iniciando contenedores Docker...",
        stopping: "Deteniendo contenedores Docker...",
        restarting: "Reiniciando contenedores Docker...",
        rebuilding: "Reconstruyendo contenedores Docker...",
        updating: "Actualizando contenedores Docker...",
        ready: "Listo",
        error: "Error",
        connecting: "Conectando..."
      }
    }
  }
};

// Web UI i18n helper class
class WebUIi18n {
  constructor() {
    this.currentLanguage = 'en';
    this.translations = webUITranslations;
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
      
      if (element.tagName === 'INPUT' && element.type === 'button') {
        element.value = translation;
      } else if (element.placeholder !== undefined) {
        element.placeholder = translation;
      } else {
        // Preserve icons if present
        const icon = element.querySelector('i');
        if (icon) {
          const iconHTML = icon.outerHTML;
          element.innerHTML = iconHTML + ' ' + translation;
        } else {
          element.textContent = translation;
        }
      }
    });
    
    // Update specific UI elements that need special handling
    this.updateSpecificElements();
  }

  updateSpecificElements() {
    // Update button tooltips
    const startBtn = document.querySelector('#start');
    const stopBtn = document.querySelector('#stop');
    const restartBtn = document.querySelector('#restart');
    const rebuildBtn = document.querySelector('#rebuild');
    const updateBtn = document.querySelector('#update');
    
    if (startBtn) startBtn.setAttribute('title', this.t('ui.start'));
    if (stopBtn) stopBtn.setAttribute('title', this.t('ui.stop'));
    if (restartBtn) restartBtn.setAttribute('title', this.t('ui.restart'));
    if (rebuildBtn) rebuildBtn.setAttribute('title', this.t('ui.rebuild'));
    if (updateBtn) updateBtn.setAttribute('title', this.t('ui.update'));
  }
}

// Create global instance
const webUIi18n = new WebUIi18n();

// Listen for interface language changes from Electron
if (window.electronAPI) {
  window.electronAPI.onInterfaceLanguageChanged((event, data) => {
    if (data.language) {
      webUIi18n.setLanguage(data.language);
    }
  });
}