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
        pdfStorageMode: "PDF Storage Mode",
        pdfStorageModeDesc: "Local uses PGVector database on your machine. Cloud uses OpenAI Vector Store API (requires additional API costs).",
        speechToText: "STT_MODEL (Speech-to-Text)",
        ttsDictPath: "TTS Dictionary File Path",
        ttsDictPathDesc: "JSON file to customize pronunciation. Maps words/phrases to phonetic spellings for better TTS output.",
        selectFile: "Select File",
        autoTtsRealtimeMode: "Auto TTS Realtime Mode",
        autoTtsRealtimeModeDesc: "When enabled, generates TTS during text streaming. When disabled (default), generates TTS after streaming completes.",
        autoTtsMinLength: "Auto TTS Buffer Size (characters)",
        autoTtsMinLengthDesc: "Minimum text length before generating TTS in realtime mode. Smaller values (20-40) provide faster response but may cause choppy audio. Larger values (60-100) improve fluency but increase initial delay. Range: 20-200 characters.",
        applicationMode: "Application Mode",
        applicationModeDesc: "Standalone runs locally. Server mode allows remote browser access via network.",
        standaloneMode: "Standalone (Default)",
        serverMode: "Server Mode",
        browserMode: "Browser Mode",
        browserModeDesc: "Internal uses built-in WebView. External opens in your default system browser.",
        internalBrowser: "Internal Browser",
        externalBrowser: "External Browser",
        extraLogging: "Extra Logging",
        extraLoggingDesc: "Enables detailed debug logging for troubleshooting. Logs saved to ~/monadic/log/extra.log.",
        enableMcpServer: "Enable MCP Server",
        enableMcpServerDesc: "Enables Model Context Protocol server for external tool integration (e.g., Claude Desktop, VS Code).",
        mcpServerPort: "MCP Server Port",
        mcpServerPortDesc: "Network port for MCP server. Change only if port 3100 conflicts with another service."
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
        pdfStorageMode: "PDFストレージモード",
        pdfStorageModeDesc: "Localはマシン上のPGVectorデータベースを使用。CloudはOpenAI Vector Store API を使用（追加のAPI利用料金が発生）。",
        speechToText: "STT_MODEL (音声認識)",
        ttsDictPath: "TTS辞書ファイルパス",
        ttsDictPathDesc: "発音をカスタマイズするJSONファイル。単語やフレーズを発音記号にマッピングしてTTS出力を改善します。",
        selectFile: "ファイル選択",
        autoTtsRealtimeMode: "自動TTSリアルタイムモード",
        autoTtsRealtimeModeDesc: "有効にすると、テキストのストリーミング中にTTSを生成します。無効（デフォルト）の場合、ストリーミング完了後にTTSを生成します。",
        autoTtsMinLength: "自動TTSバッファサイズ（文字数）",
        autoTtsMinLengthDesc: "リアルタイムモードでTTSを生成する前の最小テキスト長。小さい値（20-40）は応答が速いですが音声が途切れる可能性があります。大きい値（60-100）は流暢性が向上しますが初期遅延が増加します。範囲：20-200文字。",
        applicationMode: "アプリケーションモード",
        applicationModeDesc: "スタンドアロンはローカルで実行。サーバーモードはネットワーク経由でリモートブラウザアクセスを許可します。",
        standaloneMode: "スタンドアロン (デフォルト)",
        serverMode: "サーバーモード",
        browserMode: "ブラウザモード",
        browserModeDesc: "内部は組み込みWebViewを使用。外部はデフォルトのシステムブラウザで開きます。",
        internalBrowser: "内部ブラウザ",
        externalBrowser: "外部ブラウザ",
        extraLogging: "追加ログ",
        extraLoggingDesc: "トラブルシューティング用の詳細デバッグログを有効化。ログは~/monadic/log/extra.logに保存されます。",
        enableMcpServer: "MCPサーバーを有効化",
        enableMcpServerDesc: "外部ツール統合（Claude Desktop、VS Codeなど）のためのModel Context Protocolサーバーを有効化します。",
        mcpServerPort: "MCPサーバーポート",
        mcpServerPortDesc: "MCPサーバーのネットワークポート。ポート3100が他のサービスと競合する場合のみ変更してください。"
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
        pdfStorageMode: "PDF存储模式",
        pdfStorageModeDesc: "Local使用本地PGVector数据库。Cloud使用OpenAI Vector Store API（需要额外API费用）。",
        speechToText: "STT_MODEL (语音转文本)",
        ttsDictPath: "TTS字典文件路径",
        ttsDictPathDesc: "用于自定义发音的JSON文件。将单词/短语映射到语音拼写以改善TTS输出。",
        selectFile: "选择文件",
        autoTtsRealtimeMode: "自动TTS实时模式",
        autoTtsRealtimeModeDesc: "启用时，在文本流式传输期间生成TTS。禁用时（默认），在流式传输完成后生成TTS。",
        autoTtsMinLength: "自动TTS缓冲区大小（字符数）",
        autoTtsMinLengthDesc: "实时模式下生成TTS之前的最小文本长度。较小的值（20-40）提供更快的响应但可能导致音频断断续续。较大的值（60-100）提高流畅度但增加初始延迟。范围：20-200字符。",
        applicationMode: "应用模式",
        applicationModeDesc: "单机模式在本地运行。服务器模式允许通过网络远程浏览器访问。",
        standaloneMode: "单机模式（默认）",
        serverMode: "服务器模式",
        browserMode: "浏览器模式",
        browserModeDesc: "内部使用内置WebView。外部在默认系统浏览器中打开。",
        internalBrowser: "内部浏览器",
        externalBrowser: "外部浏览器",
        extraLogging: "额外日志",
        extraLoggingDesc: "启用详细调试日志以进行故障排除。日志保存到~/monadic/log/extra.log。",
        enableMcpServer: "启用MCP服务器",
        enableMcpServerDesc: "启用Model Context Protocol服务器以进行外部工具集成（例如Claude Desktop、VS Code）。",
        mcpServerPort: "MCP服务器端口",
        mcpServerPortDesc: "MCP服务器的网络端口。仅当端口3100与其他服务冲突时才更改。"
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
        pdfStorageMode: "PDF 저장 모드",
        pdfStorageModeDesc: "Local은 로컬 PGVector 데이터베이스를 사용합니다. Cloud는 OpenAI Vector Store API를 사용합니다(추가 API 비용 발생).",
        speechToText: "STT_MODEL (음성-텍스트 변환)",
        ttsDictPath: "TTS 사전 파일 경로",
        ttsDictPathDesc: "발음을 사용자 정의하는 JSON 파일입니다. 단어/구문을 음성 철자에 매핑하여 TTS 출력을 개선합니다.",
        selectFile: "파일 선택",
        autoTtsRealtimeMode: "자동 TTS 실시간 모드",
        autoTtsRealtimeModeDesc: "활성화하면 텍스트 스트리밍 중에 TTS를 생성합니다. 비활성화(기본값)하면 스트리밍 완료 후 TTS를 생성합니다.",
        autoTtsMinLength: "자동 TTS 버퍼 크기 (문자 수)",
        autoTtsMinLengthDesc: "실시간 모드에서 TTS를 생성하기 전 최소 텍스트 길이. 작은 값 (20-40)은 더 빠른 응답을 제공하지만 끊김이 발생할 수 있습니다. 큰 값 (60-100)은 유창성을 향상시키지만 초기 지연이 증가합니다. 범위: 20-200 문자.",
        applicationMode: "애플리케이션 모드",
        applicationModeDesc: "독립형은 로컬에서 실행됩니다. 서버 모드는 네트워크를 통한 원격 브라우저 액세스를 허용합니다.",
        standaloneMode: "독립형 (기본값)",
        serverMode: "서버 모드",
        browserMode: "브라우저 모드",
        browserModeDesc: "내부는 내장 WebView를 사용합니다. 외부는 기본 시스템 브라우저에서 엽니다.",
        internalBrowser: "내부 브라우저",
        externalBrowser: "외부 브라우저",
        extraLogging: "추가 로깅",
        extraLoggingDesc: "문제 해결을 위한 상세한 디버그 로깅을 활성화합니다. 로그는 ~/monadic/log/extra.log에 저장됩니다.",
        enableMcpServer: "MCP 서버 활성화",
        enableMcpServerDesc: "외부 도구 통합(예: Claude Desktop, VS Code)을 위한 Model Context Protocol 서버를 활성화합니다.",
        mcpServerPort: "MCP 서버 포트",
        mcpServerPortDesc: "MCP 서버의 네트워크 포트입니다. 포트 3100이 다른 서비스와 충돌하는 경우에만 변경하세요."
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
        pdfStorageMode: "Modo de Almacenamiento PDF",
        pdfStorageModeDesc: "Local usa la base de datos PGVector local. Cloud usa OpenAI Vector Store API (requiere costos adicionales de API).",
        speechToText: "STT_MODEL (Voz a Texto)",
        ttsDictPath: "Ruta del Archivo de Diccionario TTS",
        ttsDictPathDesc: "Archivo JSON para personalizar la pronunciación. Mapea palabras/frases a deletreos fonéticos para mejorar la salida TTS.",
        selectFile: "Seleccionar Archivo",
        autoTtsRealtimeMode: "Modo TTS Automático en Tiempo Real",
        autoTtsRealtimeModeDesc: "Cuando está habilitado, genera TTS durante la transmisión de texto. Cuando está deshabilitado (predeterminado), genera TTS después de que se complete la transmisión.",
        autoTtsMinLength: "Tamaño del Búfer TTS Automático (caracteres)",
        autoTtsMinLengthDesc: "Longitud mínima de texto antes de generar TTS en modo en tiempo real. Valores pequeños (20-40) proporcionan respuesta más rápida pero pueden causar audio entrecortado. Valores grandes (60-100) mejoran la fluidez pero aumentan el retraso inicial. Rango: 20-200 caracteres.",
        applicationMode: "Modo de Aplicación",
        applicationModeDesc: "Independiente se ejecuta localmente. El modo servidor permite el acceso remoto del navegador a través de la red.",
        standaloneMode: "Independiente (Predeterminado)",
        serverMode: "Modo Servidor",
        browserMode: "Modo de Navegador",
        browserModeDesc: "Interno usa WebView integrado. Externo abre en el navegador predeterminado del sistema.",
        internalBrowser: "Navegador Interno",
        externalBrowser: "Navegador Externo",
        extraLogging: "Registro Adicional",
        extraLoggingDesc: "Habilita el registro de depuración detallado para solución de problemas. Los registros se guardan en ~/monadic/log/extra.log.",
        enableMcpServer: "Habilitar Servidor MCP",
        enableMcpServerDesc: "Habilita el servidor Model Context Protocol para integración de herramientas externas (p. ej., Claude Desktop, VS Code).",
        mcpServerPort: "Puerto del Servidor MCP",
        mcpServerPortDesc: "Puerto de red para el servidor MCP. Cambie solo si el puerto 3100 entra en conflicto con otro servicio."
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
        pdfStorageMode: "Mode de Stockage PDF",
        pdfStorageModeDesc: "Local utilise la base de données PGVector locale. Cloud utilise l'API OpenAI Vector Store (nécessite des coûts API supplémentaires).",
        speechToText: "STT_MODEL (Reconnaissance Vocale)",
        ttsDictPath: "Chemin du Fichier Dictionnaire TTS",
        ttsDictPathDesc: "Fichier JSON pour personnaliser la prononciation. Mappe les mots/phrases aux orthographes phonétiques pour améliorer la sortie TTS.",
        selectFile: "Sélectionner Fichier",
        autoTtsRealtimeMode: "Mode TTS Automatique en Temps Réel",
        autoTtsRealtimeModeDesc: "Lorsqu'activé, génère le TTS pendant la diffusion du texte. Lorsque désactivé (par défaut), génère le TTS après la fin de la diffusion.",
        autoTtsMinLength: "Taille du Tampon TTS Automatique (caractères)",
        autoTtsMinLengthDesc: "Longueur minimale de texte avant de générer le TTS en mode temps réel. Les petites valeurs (20-40) fournissent une réponse plus rapide mais peuvent causer un audio saccadé. Les grandes valeurs (60-100) améliorent la fluidité mais augmentent le délai initial. Plage : 20-200 caractères.",
        applicationMode: "Mode Application",
        applicationModeDesc: "Autonome s'exécute localement. Le mode serveur permet l'accès distant par navigateur via le réseau.",
        standaloneMode: "Autonome (Par défaut)",
        serverMode: "Mode Serveur",
        browserMode: "Mode Navigateur",
        browserModeDesc: "Interne utilise WebView intégré. Externe s'ouvre dans le navigateur système par défaut.",
        internalBrowser: "Navigateur Interne",
        externalBrowser: "Navigateur Externe",
        extraLogging: "Journalisation Supplémentaire",
        extraLoggingDesc: "Active la journalisation de débogage détaillée pour le dépannage. Les journaux sont enregistrés dans ~/monadic/log/extra.log.",
        enableMcpServer: "Activer le Serveur MCP",
        enableMcpServerDesc: "Active le serveur Model Context Protocol pour l'intégration d'outils externes (par ex., Claude Desktop, VS Code).",
        mcpServerPort: "Port du Serveur MCP",
        mcpServerPortDesc: "Port réseau pour le serveur MCP. Ne modifiez que si le port 3100 entre en conflit avec un autre service."
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
        pdfStorageMode: "PDF-Speichermodus",
        pdfStorageModeDesc: "Lokal verwendet die lokale PGVector-Datenbank. Cloud verwendet die OpenAI Vector Store API (erfordert zusätzliche API-Kosten).",
        speechToText: "STT_MODEL (Spracherkennung)",
        ttsDictPath: "TTS-Wörterbuchdateipfad",
        ttsDictPathDesc: "JSON-Datei zur Anpassung der Aussprache. Ordnet Wörter/Phrasen phonetischen Schreibweisen zu, um die TTS-Ausgabe zu verbessern.",
        selectFile: "Datei auswählen",
        autoTtsRealtimeMode: "Automatischer TTS-Echtzeitmodus",
        autoTtsRealtimeModeDesc: "Wenn aktiviert, wird TTS während des Text-Streamings generiert. Wenn deaktiviert (Standard), wird TTS nach Abschluss des Streamings generiert.",
        autoTtsMinLength: "Automatische TTS-Puffergröße (Zeichen)",
        autoTtsMinLengthDesc: "Minimale Textlänge vor der TTS-Generierung im Echtzeitmodus. Kleinere Werte (20-40) bieten schnellere Antwort, können aber zu abgehacktem Audio führen. Größere Werte (60-100) verbessern die Flüssigkeit, erhöhen aber die anfängliche Verzögerung. Bereich: 20-200 Zeichen.",
        applicationMode: "Anwendungsmodus",
        applicationModeDesc: "Eigenständig läuft lokal. Server-Modus ermöglicht Fernbrowserzugriff über das Netzwerk.",
        standaloneMode: "Eigenständig (Standard)",
        serverMode: "Server-Modus",
        browserMode: "Browser-Modus",
        browserModeDesc: "Intern verwendet integrierten WebView. Extern öffnet im Standard-Systembrowser.",
        internalBrowser: "Interner Browser",
        externalBrowser: "Externer Browser",
        extraLogging: "Zusätzliche Protokollierung",
        extraLoggingDesc: "Aktiviert detaillierte Debug-Protokollierung zur Fehlerbehebung. Protokolle werden in ~/monadic/log/extra.log gespeichert.",
        enableMcpServer: "MCP-Server aktivieren",
        enableMcpServerDesc: "Aktiviert den Model Context Protocol-Server für externe Tool-Integration (z. B. Claude Desktop, VS Code).",
        mcpServerPort: "MCP-Server-Port",
        mcpServerPortDesc: "Netzwerkport für MCP-Server. Ändern Sie nur, wenn Port 3100 mit einem anderen Dienst in Konflikt steht."
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
