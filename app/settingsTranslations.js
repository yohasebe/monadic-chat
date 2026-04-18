// Settings UI Translations
const settingsTranslations = {
  en: {
    settings: {
      title: "Settings",
      loading: "Loading settings...",
      categories: {
        general: "General",
        system: "System",
        apiKeys: "API Keys",
        voice: "Voice & Audio",
        services: "Services",
        installOptions: "Install Options",
        actions: "Actions",
        about: "About"
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
        ttsDictPathDesc: "CSV file to customize pronunciation. Maps words/phrases to phonetic spellings for better TTS output.",
        selectFile: "Select File",
        autoTtsMaxBytes: "Auto TTS Max Bytes",
        autoTtsMaxBytesDesc: "Maximum text size (in bytes) for auto TTS in post-completion mode. Text exceeding this limit will be partially played or skipped. Range: 500-10000 bytes.",
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
        mcpServerPortDesc: "Network port for MCP server. Change only if port 3100 conflicts with another service.",
        openAtLogin: "Launch at Login",
        openAtLoginDesc: "Automatically start Monadic Chat when you log in to your computer.",
        menuBarMode: "Menu Bar Mode",
        menuBarModeDesc: "Hide the Dock icon and run as a menu bar app. (macOS only)",
        version: "Version",
        checkForUpdates: "Check for Updates",
        developer: "Developer",
        homepage: "Homepage",
        sourceCode: "Source Code",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Required for Concept Visualizer / Syntax Tree",
        installLatexItem: "Install LaTeX (minimal set for diagrams)",
        installPythonTitle: "Python Libraries (CPU)",
        installPythonDesc: "Pip-installed libraries for Python runtime. Models/datasets are not included.",
        installMusicTitle: "Music Analysis",
        installMusicDesc: "Required for Music Lab. Installs audio analysis libraries (chord detection, tempo/key estimation, etc.).",
        installToolsTitle: "System Tools (CLI)",
        installToolsDesc: "OS-level command-line tools available system-wide.",
        actionStatusLabel: "Docker Status",
        actionLifecycleTitle: "Container Lifecycle",
        actionStart: "Start",
        actionStop: "Stop",
        actionRestart: "Restart",
        actionBuildsTitle: "Container Builds",
        actionBuildsDesc: "Containers must be stopped before building.",
        actionBuildAll: "Build All",
        actionBuildRuby: "Build Ruby",
        actionBuildPython: "Build Python",
        actionBuildUser: "Build User",
        actionJupyterTitle: "JupyterLab",
        actionStartJupyter: "Start JupyterLab",
        actionStopJupyter: "Stop JupyterLab",
        actionDocDBTitle: "Document Database",
        actionImportDB: "Import",
        actionExportDB: "Export",
        actionNote: "Executing an action will save any unsaved settings and close this window. Progress will be shown in the main window."
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
        ok: "OK",
        actionConfirmMessage: "You have unsaved settings. Save and execute this action?",
        actionSaveAndExecute: "Save & Execute"
      }
    }
  },
  ja: {
    settings: {
      title: "設定",
      loading: "設定を読み込み中...",
      categories: {
        general: "一般",
        system: "システム",
        apiKeys: "APIキー",
        voice: "音声・オーディオ",
        services: "サービス",
        installOptions: "インストールオプション",
        actions: "アクション",
        about: "Monadic Chatについて"
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
        ttsDictPathDesc: "発音をカスタマイズするCSVファイル。単語やフレーズを発音記号にマッピングしてTTS出力を改善します。",
        selectFile: "ファイル選択",
        autoTtsMaxBytes: "自動TTS最大バイト数",
        autoTtsMaxBytesDesc: "完了後モードでの自動TTSの最大テキストサイズ（バイト）。この制限を超えるテキストは部分的に再生されるかスキップされます。範囲：500-10000バイト。",
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
        mcpServerPortDesc: "MCPサーバーのネットワークポート。ポート3100が他のサービスと競合する場合のみ変更してください。",
        openAtLogin: "ログイン時に起動",
        openAtLoginDesc: "コンピュータにログインしたときにMonadic Chatを自動的に起動します。",
        menuBarMode: "メニューバーモード",
        menuBarModeDesc: "Dockアイコンを非表示にし、メニューバーアプリとして実行します。(macOSのみ)",
        version: "バージョン",
        checkForUpdates: "アップデートを確認",
        developer: "開発者",
        homepage: "ホームページ",
        sourceCode: "ソースコード",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Concept Visualizer / Syntax Tree に必要",
        installLatexItem: "LaTeX をインストール（図表用の最小セット）",
        installPythonTitle: "Pythonライブラリ（CPU）",
        installPythonDesc: "Python実行環境のpipライブラリ。モデル/データは含まれません。",
        installMusicTitle: "音楽分析",
        installMusicDesc: "Music Lab に必要。音声分析ライブラリ（コード検出、テンポ/キー推定など）をインストールします。",
        installToolsTitle: "システムツール（CLI）",
        installToolsDesc: "OSレベルのコマンドラインツールとして利用できます。",
        actionStatusLabel: "Dockerステータス",
        actionLifecycleTitle: "コンテナの操作",
        actionStart: "開始",
        actionStop: "停止",
        actionRestart: "再起動",
        actionBuildsTitle: "コンテナのビルド",
        actionBuildsDesc: "ビルド前にコンテナを停止する必要があります。",
        actionBuildAll: "すべてビルド",
        actionBuildRuby: "Rubyをビルド",
        actionBuildPython: "Pythonをビルド",
        actionBuildUser: "ユーザーをビルド",
        actionJupyterTitle: "JupyterLab",
        actionStartJupyter: "JupyterLabを開始",
        actionStopJupyter: "JupyterLabを停止",
        actionDocDBTitle: "ドキュメントデータベース",
        actionImportDB: "インポート",
        actionExportDB: "エクスポート",
        actionNote: "アクションを実行すると、未保存の設定を保存してこのウィンドウを閉じます。進捗はメインウィンドウに表示されます。"
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
        ok: "OK",
        actionConfirmMessage: "未保存の設定があります。保存してからアクションを実行しますか？",
        actionSaveAndExecute: "保存して実行"
      }
    }
  },
  zh: {
    settings: {
      title: "设置",
      loading: "加载设置中...",
      categories: {
        general: "通用",
        system: "系统",
        apiKeys: "API密钥",
        voice: "语音和音频",
        services: "服务",
        installOptions: "安装选项",
        actions: "操作",
        about: "关于"
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
        ttsDictPathDesc: "用于自定义发音的CSV文件。将单词/短语映射到语音拼写以改善TTS输出。",
        selectFile: "选择文件",
        autoTtsMaxBytes: "自动TTS最大字节数",
        autoTtsMaxBytesDesc: "完成后模式下自动TTS的最大文本大小（字节）。超过此限制的文本将部分播放或跳过。范围：500-10000字节。",
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
        mcpServerPortDesc: "MCP服务器的网络端口。仅当端口3100与其他服务冲突时才更改。",
        openAtLogin: "登录时启动",
        openAtLoginDesc: "登录计算机时自动启动Monadic Chat。",
        menuBarMode: "菜单栏模式",
        menuBarModeDesc: "隐藏Dock图标，作为菜单栏应用运行。(仅限macOS)",
        version: "版本",
        checkForUpdates: "检查更新",
        developer: "开发者",
        homepage: "主页",
        sourceCode: "源代码",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Concept Visualizer / Syntax Tree 需要",
        installLatexItem: "安装 LaTeX（用于图表的最小集）",
        installPythonTitle: "Python 库（CPU）",
        installPythonDesc: "用于 Python 运行时的 pip 库。不包含模型/数据。",
        installMusicTitle: "音乐分析",
        installMusicDesc: "Music Lab 需要。安装音频分析库（和弦检测、节拍/调性估算等）。",
        installToolsTitle: "系统工具（CLI）",
        installToolsDesc: "操作系统层面的命令行工具，系统范围可用。",
        actionStatusLabel: "Docker 状态",
        actionLifecycleTitle: "容器生命周期",
        actionStart: "启动",
        actionStop: "停止",
        actionRestart: "重启",
        actionBuildsTitle: "容器构建",
        actionBuildsDesc: "构建前必须停止容器。",
        actionBuildAll: "全部构建",
        actionBuildRuby: "构建 Ruby",
        actionBuildPython: "构建 Python",
        actionBuildUser: "构建用户容器",
        actionJupyterTitle: "JupyterLab",
        actionStartJupyter: "启动 JupyterLab",
        actionStopJupyter: "停止 JupyterLab",
        actionDocDBTitle: "文档数据库",
        actionImportDB: "导入",
        actionExportDB: "导出",
        actionNote: "执行操作将保存未保存的设置并关闭此窗口。进度将显示在主窗口中。"
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
        ok: "确定",
        actionConfirmMessage: "您有未保存的设置。是否保存并执行此操作？",
        actionSaveAndExecute: "保存并执行"
      }
    }
  },
  ko: {
    settings: {
      title: "설정",
      loading: "설정 로드 중...",
      categories: {
        general: "일반",
        system: "시스템",
        apiKeys: "API 키",
        voice: "음성 및 오디오",
        services: "서비스",
        installOptions: "설치 옵션",
        actions: "작업",
        about: "정보"
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
        ttsDictPathDesc: "발음을 사용자 정의하는 CSV 파일입니다. 단어/구문을 음성 철자에 매핑하여 TTS 출력을 개선합니다.",
        selectFile: "파일 선택",
        autoTtsMaxBytes: "자동 TTS 최대 바이트",
        autoTtsMaxBytesDesc: "완료 후 모드에서 자동 TTS의 최대 텍스트 크기(바이트). 이 제한을 초과하는 텍스트는 일부만 재생되거나 건너뜁니다. 범위: 500-10000 바이트.",
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
        mcpServerPortDesc: "MCP 서버의 네트워크 포트입니다. 포트 3100이 다른 서비스와 충돌하는 경우에만 변경하세요.",
        openAtLogin: "로그인 시 시작",
        openAtLoginDesc: "컴퓨터에 로그인할 때 Monadic Chat를 자동으로 시작합니다.",
        menuBarMode: "메뉴 바 모드",
        menuBarModeDesc: "Dock 아이콘을 숨기고 메뉴 바 앱으로 실행합니다. (macOS 전용)",
        version: "버전",
        checkForUpdates: "업데이트 확인",
        developer: "개발자",
        homepage: "홈페이지",
        sourceCode: "소스 코드",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Concept Visualizer / Syntax Tree에 필요",
        installLatexItem: "LaTeX 설치 (도표용 최소 세트)",
        installPythonTitle: "Python 라이브러리 (CPU)",
        installPythonDesc: "Python 런타임용 pip 라이브러리입니다. 모델/데이터는 포함되지 않습니다.",
        installMusicTitle: "음악 분석",
        installMusicDesc: "Music Lab에 필요합니다. 오디오 분석 라이브러리를 설치합니다 (코드 감지, 템포/키 추정 등).",
        installToolsTitle: "시스템 도구 (CLI)",
        installToolsDesc: "OS 수준의 명령줄 도구를 전체 시스템에서 사용할 수 있습니다.",
        actionStatusLabel: "Docker 상태",
        actionLifecycleTitle: "컨테이너 수명주기",
        actionStart: "시작",
        actionStop: "중지",
        actionRestart: "재시작",
        actionBuildsTitle: "컨테이너 빌드",
        actionBuildsDesc: "빌드 전에 컨테이너를 중지해야 합니다.",
        actionBuildAll: "모두 빌드",
        actionBuildRuby: "Ruby 빌드",
        actionBuildPython: "Python 빌드",
        actionBuildUser: "사용자 빌드",
        actionJupyterTitle: "JupyterLab",
        actionStartJupyter: "JupyterLab 시작",
        actionStopJupyter: "JupyterLab 중지",
        actionDocDBTitle: "문서 데이터베이스",
        actionImportDB: "가져오기",
        actionExportDB: "내보내기",
        actionNote: "작업을 실행하면 저장되지 않은 설정을 저장하고 이 창을 닫습니다. 진행 상황은 메인 창에 표시됩니다."
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
        ok: "확인",
        actionConfirmMessage: "저장되지 않은 설정이 있습니다. 저장하고 작업을 실행하시겠습니까?",
        actionSaveAndExecute: "저장 후 실행"
      }
    }
  },
  es: {
    settings: {
      title: "Configuración",
      loading: "Cargando configuración...",
      categories: {
        general: "General",
        system: "Sistema",
        apiKeys: "Claves API",
        voice: "Voz y Audio",
        services: "Servicios",
        installOptions: "Opciones de Instalación",
        actions: "Acciones",
        about: "Acerca de"
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
        ttsDictPathDesc: "Archivo CSV para personalizar la pronunciación. Mapea palabras/frases a deletreos fonéticos para mejorar la salida TTS.",
        selectFile: "Seleccionar Archivo",
        autoTtsMaxBytes: "Bytes Máximos de TTS Automático",
        autoTtsMaxBytesDesc: "Tamaño máximo de texto (en bytes) para TTS automático en modo posterior a la finalización. El texto que exceda este límite se reproducirá parcialmente o se omitirá. Rango: 500-10000 bytes.",
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
        mcpServerPortDesc: "Puerto de red para el servidor MCP. Cambie solo si el puerto 3100 entra en conflicto con otro servicio.",
        openAtLogin: "Iniciar al iniciar sesión",
        openAtLoginDesc: "Inicia automáticamente Monadic Chat cuando inicias sesión en tu computadora.",
        menuBarMode: "Modo Barra de Menú",
        menuBarModeDesc: "Oculta el icono del Dock y ejecuta como aplicación de barra de menú. (solo macOS)",
        version: "Versión",
        checkForUpdates: "Buscar Actualizaciones",
        developer: "Desarrollador",
        homepage: "Página principal",
        sourceCode: "Código fuente",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Requerido para Concept Visualizer / Syntax Tree",
        installLatexItem: "Instalar LaTeX (conjunto mínimo para diagramas)",
        installPythonTitle: "Librerías de Python (CPU)",
        installPythonDesc: "Librerías instaladas con pip para el entorno de Python. No incluye modelos/datos.",
        installMusicTitle: "Análisis musical",
        installMusicDesc: "Requerido para Music Lab. Instala bibliotecas de análisis de audio (detección de acordes, estimación de tempo/tonalidad, etc.).",
        installToolsTitle: "Herramientas del sistema (CLI)",
        installToolsDesc: "Herramientas de línea de comandos a nivel del sistema, disponibles globalmente.",
        actionStatusLabel: "Estado de Docker",
        actionLifecycleTitle: "Ciclo de vida de contenedores",
        actionStart: "Iniciar",
        actionStop: "Detener",
        actionRestart: "Reiniciar",
        actionBuildsTitle: "Construcción de contenedores",
        actionBuildsDesc: "Los contenedores deben estar detenidos antes de construir.",
        actionBuildAll: "Construir todo",
        actionBuildRuby: "Construir Ruby",
        actionBuildPython: "Construir Python",
        actionBuildUser: "Construir usuario",
        actionJupyterTitle: "JupyterLab",
        actionStartJupyter: "Iniciar JupyterLab",
        actionStopJupyter: "Detener JupyterLab",
        actionDocDBTitle: "Base de datos de documentos",
        actionImportDB: "Importar",
        actionExportDB: "Exportar",
        actionNote: "Ejecutar una acción guardará la configuración no guardada y cerrará esta ventana. El progreso se mostrará en la ventana principal."
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
        ok: "OK",
        actionConfirmMessage: "Tiene configuraciones sin guardar. ¿Guardar y ejecutar esta acción?",
        actionSaveAndExecute: "Guardar y ejecutar"
      }
    }
  },
  fr: {
    settings: {
      title: "Paramètres",
      loading: "Chargement des paramètres...",
      categories: {
        general: "Général",
        system: "Système",
        apiKeys: "Clés API",
        voice: "Voix et Audio",
        services: "Services",
        installOptions: "Options d'Installation",
        actions: "Actions",
        about: "À propos"
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
        ttsDictPathDesc: "Fichier CSV pour personnaliser la prononciation. Mappe les mots/phrases aux orthographes phonétiques pour améliorer la sortie TTS.",
        selectFile: "Sélectionner Fichier",
        autoTtsMaxBytes: "Octets Maximum TTS Automatique",
        autoTtsMaxBytesDesc: "Taille maximale du texte (en octets) pour le TTS automatique en mode post-achèvement. Le texte dépassant cette limite sera partiellement lu ou ignoré. Plage : 500-10000 octets.",
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
        mcpServerPortDesc: "Port réseau pour le serveur MCP. Ne modifiez que si le port 3100 entre en conflit avec un autre service.",
        openAtLogin: "Lancer au démarrage",
        openAtLoginDesc: "Démarre automatiquement Monadic Chat lorsque vous vous connectez à votre ordinateur.",
        menuBarMode: "Mode Barre de Menu",
        menuBarModeDesc: "Masque l'icône du Dock et s'exécute comme application de barre de menu. (macOS uniquement)",
        version: "Version",
        checkForUpdates: "Vérifier les mises à jour",
        developer: "Développeur",
        homepage: "Page d'accueil",
        sourceCode: "Code source",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Nécessaire pour Concept Visualizer / Syntax Tree",
        installLatexItem: "Installer LaTeX (ensemble minimal pour les diagrammes)",
        installPythonTitle: "Bibliothèques Python (CPU)",
        installPythonDesc: "Bibliothèques pip pour l'environnement Python. Modèles/données non inclus.",
        installMusicTitle: "Analyse musicale",
        installMusicDesc: "Requis pour Music Lab. Installe les bibliothèques d'analyse audio (détection d'accords, estimation du tempo/tonalité, etc.).",
        installToolsTitle: "Outils système (CLI)",
        installToolsDesc: "Outils en ligne de commande au niveau du système, disponibles globalement.",
        actionStatusLabel: "État de Docker",
        actionLifecycleTitle: "Cycle de vie des conteneurs",
        actionStart: "Démarrer",
        actionStop: "Arrêter",
        actionRestart: "Redémarrer",
        actionBuildsTitle: "Construction des conteneurs",
        actionBuildsDesc: "Les conteneurs doivent être arrêtés avant la construction.",
        actionBuildAll: "Tout construire",
        actionBuildRuby: "Construire Ruby",
        actionBuildPython: "Construire Python",
        actionBuildUser: "Construire utilisateur",
        actionJupyterTitle: "JupyterLab",
        actionStartJupyter: "Démarrer JupyterLab",
        actionStopJupyter: "Arrêter JupyterLab",
        actionDocDBTitle: "Base de données de documents",
        actionImportDB: "Importer",
        actionExportDB: "Exporter",
        actionNote: "L'exécution d'une action enregistrera les paramètres non sauvegardés et fermera cette fenêtre. La progression sera affichée dans la fenêtre principale."
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
        ok: "OK",
        actionConfirmMessage: "Vous avez des paramètres non enregistrés. Enregistrer et exécuter cette action ?",
        actionSaveAndExecute: "Enregistrer et exécuter"
      }
    }
  },
  de: {
    settings: {
      title: "Einstellungen",
      loading: "Einstellungen werden geladen...",
      categories: {
        general: "Allgemein",
        system: "System",
        apiKeys: "API-Schlüssel",
        voice: "Sprache und Audio",
        services: "Dienste",
        installOptions: "Installationsoptionen",
        actions: "Aktionen",
        about: "Über"
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
        ttsDictPathDesc: "CSV-Datei zur Anpassung der Aussprache. Ordnet Wörter/Phrasen phonetischen Schreibweisen zu, um die TTS-Ausgabe zu verbessern.",
        selectFile: "Datei auswählen",
        autoTtsMaxBytes: "Automatische TTS Maximale Bytes",
        autoTtsMaxBytesDesc: "Maximale Textgröße (in Bytes) für automatisches TTS im Nachvervollständigungsmodus. Text, der dieses Limit überschreitet, wird teilweise abgespielt oder übersprungen. Bereich: 500-10000 Bytes.",
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
        mcpServerPortDesc: "Netzwerkport für MCP-Server. Ändern Sie nur, wenn Port 3100 mit einem anderen Dienst in Konflikt steht.",
        openAtLogin: "Bei Anmeldung starten",
        openAtLoginDesc: "Startet Monadic Chat automatisch, wenn Sie sich an Ihrem Computer anmelden.",
        menuBarMode: "Menüleisten-Modus",
        menuBarModeDesc: "Blendet das Dock-Symbol aus und führt die App als Menüleisten-App aus. (nur macOS)",
        version: "Version",
        checkForUpdates: "Nach Updates suchen",
        developer: "Entwickler",
        homepage: "Startseite",
        sourceCode: "Quellcode",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Erforderlich für Concept Visualizer / Syntax Tree",
        installLatexItem: "LaTeX installieren (Minimalsatz für Diagramme)",
        installPythonTitle: "Python-Bibliotheken (CPU)",
        installPythonDesc: "Per pip installierte Bibliotheken für die Python-Laufzeit. Modelle/Datasets sind nicht enthalten.",
        installMusicTitle: "Musikanalyse",
        installMusicDesc: "Erforderlich für Music Lab. Installiert Audioanalyse-Bibliotheken (Akkorderkennung, Tempo-/Tonarterkennung usw.).",
        installToolsTitle: "Systemwerkzeuge (CLI)",
        installToolsDesc: "Befehlszeilenwerkzeuge auf Betriebssystemebene, systemweit verfügbar.",
        actionStatusLabel: "Docker-Status",
        actionLifecycleTitle: "Container-Lebenszyklus",
        actionStart: "Starten",
        actionStop: "Stoppen",
        actionRestart: "Neustarten",
        actionBuildsTitle: "Container erstellen",
        actionBuildsDesc: "Container müssen vor dem Erstellen gestoppt werden.",
        actionBuildAll: "Alles erstellen",
        actionBuildRuby: "Ruby erstellen",
        actionBuildPython: "Python erstellen",
        actionBuildUser: "Benutzer erstellen",
        actionJupyterTitle: "JupyterLab",
        actionStartJupyter: "JupyterLab starten",
        actionStopJupyter: "JupyterLab stoppen",
        actionDocDBTitle: "Dokumentendatenbank",
        actionImportDB: "Importieren",
        actionExportDB: "Exportieren",
        actionNote: "Das Ausführen einer Aktion speichert nicht gespeicherte Einstellungen und schließt dieses Fenster. Der Fortschritt wird im Hauptfenster angezeigt."
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
        ok: "OK",
        actionConfirmMessage: "Sie haben nicht gespeicherte Einstellungen. Speichern und diese Aktion ausführen?",
        actionSaveAndExecute: "Speichern & Ausführen"
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
