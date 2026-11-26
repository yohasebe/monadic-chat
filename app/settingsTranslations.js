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
        ttsDictPath: "TTS Dictionary File Path",
        ttsDictPathDesc: "CSV file to customize pronunciation. Maps words/phrases to phonetic spellings for better TTS output.",
        selectFile: "Select File",
        autoTtsMaxBytes: "Auto TTS Max Bytes",
        autoTtsMaxBytesDesc: "Maximum text size (in bytes) for auto TTS in post-completion mode. Text exceeding this limit will be partially played or skipped. Range: 500-10000 bytes.",
        browserMode: "Browser Mode",
        browserModeDesc: "Internal uses built-in WebView. External opens in your default system browser.",
        internalBrowser: "Internal Browser",
        externalBrowser: "External Browser",
        extraLogging: "Extra Logging",
        aiSources: "Sources the AI can use",
        libraryInChats: "The Library, in chats",
        libraryInChatsDesc: "When on, the AI consults the Library when you ask for it or it clearly helps, and what it reads is shown on the work screen. Takes effect when Monadic Chat starts again.",
        extraLoggingDesc: "Enables detailed debug logging for troubleshooting. Logs saved to ~/monadic/log/extra.log.",
        enableMcpServer: "Enable MCP Server",
        enableMcpServerDesc: "Enables Model Context Protocol server for external tool integration (e.g., Claude Desktop, VS Code).",
        mcpServerPort: "MCP Server Port",
        mcpServerPortDesc: "Network port for MCP server. Change only if port 3100 conflicts with another service.",
        openAtLogin: "Launch at Login",
        openAtLoginDesc: "Automatically start Monadic Chat when you log in to your computer.",
        menuBarMode: "Menu Bar Mode",
        menuBarModeDesc: "Hide the Dock icon and run as a menu bar app. (macOS only)",
        backgroundReplyNotifications: "Notify When a Reply Arrives in the Background",
        backgroundReplyNotificationsDesc: "Closing the Web UI hides it, and a reply in progress keeps coming in. Show a notification when it arrives.",
        version: "Version",
        checkForUpdates: "Check for Updates",
        developer: "Developer",
        homepage: "Homepage",
        sourceCode: "Source Code",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Required for Concept Visualizer",
        installLatexItem: "Install LaTeX (minimal set for diagrams)",
        installPythonTitle: "Python Libraries (CPU)",
        installPythonDesc: "Pip-installed libraries for Python runtime. Models/datasets are not included.",
        installMusicTitle: "Music Analysis",
        installMusicDesc: "Required for Music Tutor and Music Analyst. Installs audio analysis libraries (chord detection, tempo/key estimation, etc.).",
        installToolsTitle: "System Tools (CLI)",
        installToolsDesc: "OS-level command-line tools available system-wide.",
        installPrivacyTitle: "Name Finder — Additional Languages",
        installPrivacyDesc: "English is always enabled. Enable additional languages to find names to hide in messages in other languages. All language models are preinstalled in the Privacy container; changes apply when you save — no rebuild needed.",
        installExtractorTitle: "Knowledge Base Quality Pack (Docling)",
        installExtractorDesc: "Layout-aware PDF extraction with OCR, table structure, and multilingual support. Adds a separate ~3 GB container; Library imports use it when installed.",
        installExtractorEnable: "Install Knowledge Base Quality Pack",
        installExtractorLangsLabel: "OCR languages (RapidOCR; default covers East Asian + English)",
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
        actionBuildPrivacy: "Build Privacy",
        actionBuildExtractor: "Build Extractor",
        actionJupyterTitle: "JupyterLab",
        actionOpenJupyter: "Open JupyterLab",
        actionStopJupyter: "Stop JupyterLab",
        actionDocDBTitle: "Document Database",
        actionImportDB: "Import",
        actionExportDB: "Export",
        actionNote: "Executing an action will save any unsaved settings and close this window. Progress will be shown in the main window."
      },
      keyCheck: {
        check: "Check",
        checking: "Checking…",
        checkHint: "Sends the key in this field to this field's provider",
        heading: "Default models of this provider (apps may name their own)",
        envSource: "set by {name}",
        defaultsUnavailable: "The list of default models could not be read.",
        status: {
          accepted: "Key accepted",
          rejected: "Key rejected by the provider",
          forbidden: "This key cannot use the check (no permission or a restriction); it may still be valid",
          rateLimited: "Rate limited; try again later",
          serviceError: "The provider had an error; try again later",
          timeout: "No answer in time",
          unreachable: "Could not reach the provider",
          unexpected: "The provider's answer could not be read",
          invalidInput: "Enter a key first",
          opFailed: "Could not read the key from 1Password",
          busy: "Already checking",
          unsupported: "This key cannot be checked"
        },
        result: {
          listed: "In this key's list",
          notListed: "Not in this key's list",
          notCheckable: "Not shown in the list",
          unknown: "Unknown"
        },
        op: {
          opMissing: "1Password CLI not found",
          notSignedIn: "not signed in",
          cancelled: "cancelled",
          notFound: "reference not found",
          timeout: "timed out",
          failed: "failed"
        },
        categories: {
          chat: "Chat",
          code: "Code",
          vision: "Vision",
          image: "Image",
          video: "Video",
          tts: "Speech",
          audio_transcription: "Transcription",
          music: "Music"
        }
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
        ttsDictPath: "TTS辞書ファイルパス",
        ttsDictPathDesc: "発音をカスタマイズするCSVファイル。単語やフレーズを発音記号にマッピングしてTTS出力を改善します。",
        selectFile: "ファイル選択",
        autoTtsMaxBytes: "自動TTS最大バイト数",
        autoTtsMaxBytesDesc: "完了後モードでの自動TTSの最大テキストサイズ（バイト）。この制限を超えるテキストは部分的に再生されるかスキップされます。範囲：500-10000バイト。",
        browserMode: "ブラウザモード",
        browserModeDesc: "内部は組み込みWebViewを使用。外部はデフォルトのシステムブラウザで開きます。",
        internalBrowser: "内部ブラウザ",
        externalBrowser: "外部ブラウザ",
        extraLogging: "追加ログ",
        aiSources: "AI が使える情報源",
        libraryInChats: "書庫（会話の中で）",
        libraryInChatsDesc: "オンのとき、頼まれたときや明らかに役立つときに AI が書庫を参照し、読んだものは作業画面に表示されます。Monadic Chat を起動し直すと反映されます。",
        extraLoggingDesc: "トラブルシューティング用の詳細デバッグログを有効化。ログは~/monadic/log/extra.logに保存されます。",
        enableMcpServer: "MCPサーバーを有効化",
        enableMcpServerDesc: "外部ツール統合（Claude Desktop、VS Codeなど）のためのModel Context Protocolサーバーを有効化します。",
        mcpServerPort: "MCPサーバーポート",
        mcpServerPortDesc: "MCPサーバーのネットワークポート。ポート3100が他のサービスと競合する場合のみ変更してください。",
        openAtLogin: "ログイン時に起動",
        openAtLoginDesc: "コンピュータにログインしたときにMonadic Chatを自動的に起動します。",
        menuBarMode: "メニューバーモード",
        menuBarModeDesc: "Dockアイコンを非表示にし、メニューバーアプリとして実行します。(macOSのみ)",
        backgroundReplyNotifications: "裏で届いた返事を通知",
        backgroundReplyNotificationsDesc: "Web UI を閉じると隠れ、作っていた返事は受け取り続けます。届いたときに通知を出します。",
        version: "バージョン",
        checkForUpdates: "アップデートを確認",
        developer: "開発者",
        homepage: "ホームページ",
        sourceCode: "ソースコード",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Concept Visualizer に必要",
        installLatexItem: "LaTeX をインストール（図表用の最小セット）",
        installPythonTitle: "Pythonライブラリ（CPU）",
        installPythonDesc: "Python実行環境のpipライブラリ。モデル/データは含まれません。",
        installMusicTitle: "音楽分析",
        installMusicDesc: "Music Tutor と Music Analyst に必要。音声分析ライブラリ（コード検出、テンポ/キー推定など）をインストールします。",
        installToolsTitle: "システムツール（CLI）",
        installToolsDesc: "OSレベルのコマンドラインツールとして利用できます。",
        installPrivacyTitle: "名前の検出 — 追加言語",
        installPrivacyDesc: "英語は常に有効です。英語以外のメッセージで伏せる名前を探すには、追加言語を有効にしてください。全言語のモデルは Privacy コンテナにプリインストール済みで、変更は保存時に反映されます（リビルド不要）。",
        installExtractorTitle: "Knowledge Base 品質パック (Docling)",
        installExtractorDesc: "OCR・表構造抽出・多言語対応のレイアウト解析を行う PDF 抽出器。約 3 GB の専用コンテナが追加され、Library のインポートで使用されます。",
        installExtractorEnable: "Knowledge Base 品質パックをインストール",
        installExtractorLangsLabel: "OCR 言語（RapidOCR、既定は英語＋東アジア）",
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
        actionBuildPrivacy: "プライバシーをビルド",
        actionBuildExtractor: "Extractor をビルド",
        actionJupyterTitle: "JupyterLab",
        actionOpenJupyter: "JupyterLab を開く",
        actionStopJupyter: "JupyterLabを停止",
        actionDocDBTitle: "ドキュメントデータベース",
        actionImportDB: "インポート",
        actionExportDB: "エクスポート",
        actionNote: "アクションを実行すると、未保存の設定を保存してこのウィンドウを閉じます。進捗はメインウィンドウに表示されます。"
      },
      keyCheck: {
        check: "確認",
        checking: "確認中…",
        checkHint: "この欄のキーを、この欄の提供元に送って確かめます",
        heading: "この提供元の既定のモデル（アプリが個別に指定する場合があります）",
        envSource: "{name} で指定",
        defaultsUnavailable: "既定のモデルの一覧を読めませんでした。",
        status: {
          accepted: "キーは受け付けられました",
          rejected: "提供元がキーを拒否しました",
          forbidden: "このキーでは確認できません（権限または制限）。キー自体は有効な場合があります",
          rateLimited: "回数の制限に達しました。しばらくして再度お試しください",
          serviceError: "提供元でエラーが起きました。しばらくして再度お試しください",
          timeout: "時間内に応答がありませんでした",
          unreachable: "提供元に接続できませんでした",
          unexpected: "提供元の応答を読めませんでした",
          invalidInput: "先にキーを入力してください",
          opFailed: "1Password からキーを読めませんでした",
          busy: "確認中です",
          unsupported: "このキーは確認できません"
        },
        result: {
          listed: "このキーの一覧にあります",
          notListed: "このキーの一覧にありません",
          notCheckable: "一覧には載りません",
          unknown: "不明"
        },
        op: {
          opMissing: "1Password CLI が見つかりません",
          notSignedIn: "サインインしていません",
          cancelled: "取り消されました",
          notFound: "参照が見つかりません",
          timeout: "時間切れ",
          failed: "失敗"
        },
        categories: {
          chat: "会話",
          code: "コード",
          vision: "画像の理解",
          image: "画像生成",
          video: "動画",
          tts: "読み上げ",
          audio_transcription: "文字起こし",
          music: "音楽"
        }
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
        ttsDictPath: "TTS字典文件路径",
        ttsDictPathDesc: "用于自定义发音的CSV文件。将单词/短语映射到语音拼写以改善TTS输出。",
        selectFile: "选择文件",
        autoTtsMaxBytes: "自动TTS最大字节数",
        autoTtsMaxBytesDesc: "完成后模式下自动TTS的最大文本大小（字节）。超过此限制的文本将部分播放或跳过。范围：500-10000字节。",
        browserMode: "浏览器模式",
        browserModeDesc: "内部使用内置WebView。外部在默认系统浏览器中打开。",
        internalBrowser: "内部浏览器",
        externalBrowser: "外部浏览器",
        extraLogging: "额外日志",
        aiSources: "AI 可用的信息来源",
        libraryInChats: "资料库（对话中）",
        libraryInChatsDesc: "开启后，AI 会在你要求或明显有帮助时参考资料库，读到的内容显示在工作画面上。重新启动 Monadic Chat 后生效。",
        extraLoggingDesc: "启用详细调试日志以进行故障排除。日志保存到~/monadic/log/extra.log。",
        enableMcpServer: "启用MCP服务器",
        enableMcpServerDesc: "启用Model Context Protocol服务器以进行外部工具集成（例如Claude Desktop、VS Code）。",
        mcpServerPort: "MCP服务器端口",
        mcpServerPortDesc: "MCP服务器的网络端口。仅当端口3100与其他服务冲突时才更改。",
        openAtLogin: "登录时启动",
        openAtLoginDesc: "登录计算机时自动启动Monadic Chat。",
        menuBarMode: "菜单栏模式",
        menuBarModeDesc: "隐藏Dock图标，作为菜单栏应用运行。(仅限macOS)",
        backgroundReplyNotifications: "后台收到回复时通知",
        backgroundReplyNotificationsDesc: "关闭 Web UI 时它会隐藏，正在生成的回复会继续接收。收到时显示通知。",
        version: "版本",
        checkForUpdates: "检查更新",
        developer: "开发者",
        homepage: "主页",
        sourceCode: "源代码",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Concept Visualizer 需要",
        installLatexItem: "安装 LaTeX（用于图表的最小集）",
        installPythonTitle: "Python 库（CPU）",
        installPythonDesc: "用于 Python 运行时的 pip 库。不包含模型/数据。",
        installMusicTitle: "音乐分析",
        installMusicDesc: "Music Tutor 和 Music Analyst 需要。安装音频分析库（和弦检测、节拍/调性估算等）。",
        installToolsTitle: "系统工具（CLI）",
        installToolsDesc: "操作系统层面的命令行工具，系统范围可用。",
        installPrivacyTitle: "名称识别 — 附加语言",
        installPrivacyDesc: "英语始终启用。启用附加语言后，可在非英语消息中查找要隐藏的名称。所有语言模型已预装在 Privacy 容器中；更改在保存时生效，无需重新构建。",
        installExtractorTitle: "知识库质量包 (Docling)",
        installExtractorDesc: "支持 OCR、表格结构识别和多语言的布局感知 PDF 提取。会增加约 3 GB 的独立容器；安装后 Library 导入会自动使用。",
        installExtractorEnable: "安装知识库质量包",
        installExtractorLangsLabel: "OCR 语言（RapidOCR；默认覆盖东亚语言和英语）",
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
        actionBuildPrivacy: "构建隐私",
        actionBuildExtractor: "构建提取器",
        actionJupyterTitle: "JupyterLab",
        actionOpenJupyter: "打开 JupyterLab",
        actionStopJupyter: "停止 JupyterLab",
        actionDocDBTitle: "文档数据库",
        actionImportDB: "导入",
        actionExportDB: "导出",
        actionNote: "执行操作将保存未保存的设置并关闭此窗口。进度将显示在主窗口中。"
      },
      keyCheck: {
        check: "检查",
        checking: "检查中…",
        checkHint: "将此栏中的密钥发送给此栏对应的提供商进行检查",
        heading: "此提供商的默认模型（应用可能指定自己的模型）",
        envSource: "由 {name} 设置",
        defaultsUnavailable: "无法读取默认模型列表。",
        status: {
          accepted: "密钥已被接受",
          rejected: "提供商拒绝了该密钥",
          forbidden: "此密钥无法用于检查（无权限或受限），密钥本身可能仍有效",
          rateLimited: "已达到速率限制，请稍后再试",
          serviceError: "提供商出现错误，请稍后再试",
          timeout: "未及时响应",
          unreachable: "无法连接到提供商",
          unexpected: "无法读取提供商的响应",
          invalidInput: "请先输入密钥",
          opFailed: "无法从 1Password 读取密钥",
          busy: "正在检查",
          unsupported: "无法检查此密钥"
        },
        result: {
          listed: "在此密钥的列表中",
          notListed: "不在此密钥的列表中",
          notCheckable: "不在列表中显示",
          unknown: "未知"
        },
        op: {
          opMissing: "未找到 1Password CLI",
          notSignedIn: "未登录",
          cancelled: "已取消",
          notFound: "未找到引用",
          timeout: "超时",
          failed: "失败"
        },
        categories: {
          chat: "对话",
          code: "代码",
          vision: "图像理解",
          image: "图像生成",
          video: "视频",
          tts: "语音合成",
          audio_transcription: "转录",
          music: "音乐"
        }
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
        ttsDictPath: "TTS 사전 파일 경로",
        ttsDictPathDesc: "발음을 사용자 정의하는 CSV 파일입니다. 단어/구문을 음성 철자에 매핑하여 TTS 출력을 개선합니다.",
        selectFile: "파일 선택",
        autoTtsMaxBytes: "자동 TTS 최대 바이트",
        autoTtsMaxBytesDesc: "완료 후 모드에서 자동 TTS의 최대 텍스트 크기(바이트). 이 제한을 초과하는 텍스트는 일부만 재생되거나 건너뜁니다. 범위: 500-10000 바이트.",
        browserMode: "브라우저 모드",
        browserModeDesc: "내부는 내장 WebView를 사용합니다. 외부는 기본 시스템 브라우저에서 엽니다.",
        internalBrowser: "내부 브라우저",
        externalBrowser: "외부 브라우저",
        extraLogging: "추가 로깅",
        aiSources: "AI가 쓸 수 있는 정보원",
        libraryInChats: "라이브러리(대화 중)",
        libraryInChatsDesc: "켜면 요청하거나 분명히 도움이 될 때 AI가 라이브러리를 참고하고, 읽은 내용은 작업 화면에 표시됩니다. Monadic Chat을 다시 시작하면 적용됩니다.",
        extraLoggingDesc: "문제 해결을 위한 상세한 디버그 로깅을 활성화합니다. 로그는 ~/monadic/log/extra.log에 저장됩니다.",
        enableMcpServer: "MCP 서버 활성화",
        enableMcpServerDesc: "외부 도구 통합(예: Claude Desktop, VS Code)을 위한 Model Context Protocol 서버를 활성화합니다.",
        mcpServerPort: "MCP 서버 포트",
        mcpServerPortDesc: "MCP 서버의 네트워크 포트입니다. 포트 3100이 다른 서비스와 충돌하는 경우에만 변경하세요.",
        openAtLogin: "로그인 시 시작",
        openAtLoginDesc: "컴퓨터에 로그인할 때 Monadic Chat를 자동으로 시작합니다.",
        menuBarMode: "메뉴 바 모드",
        menuBarModeDesc: "Dock 아이콘을 숨기고 메뉴 바 앱으로 실행합니다. (macOS 전용)",
        backgroundReplyNotifications: "백그라운드에서 답변이 도착하면 알림",
        backgroundReplyNotificationsDesc: "Web UI를 닫으면 숨겨지고, 작성 중인 답변은 계속 받습니다. 도착하면 알림을 표시합니다.",
        version: "버전",
        checkForUpdates: "업데이트 확인",
        developer: "개발자",
        homepage: "홈페이지",
        sourceCode: "소스 코드",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Concept Visualizer에 필요",
        installLatexItem: "LaTeX 설치 (도표용 최소 세트)",
        installPythonTitle: "Python 라이브러리 (CPU)",
        installPythonDesc: "Python 런타임용 pip 라이브러리입니다. 모델/데이터는 포함되지 않습니다.",
        installMusicTitle: "음악 분석",
        installMusicDesc: "Music Tutor와 Music Analyst에 필요합니다. 오디오 분석 라이브러리를 설치합니다 (코드 감지, 템포/키 추정 등).",
        installToolsTitle: "시스템 도구 (CLI)",
        installToolsDesc: "OS 수준의 명령줄 도구를 전체 시스템에서 사용할 수 있습니다.",
        installPrivacyTitle: "이름 찾기 — 추가 언어",
        installPrivacyDesc: "영어는 항상 활성화됩니다. 영어 이외의 메시지에서 숨길 이름을 찾으려면 추가 언어를 활성화하세요. 모든 언어 모델은 Privacy 컨테이너에 사전 설치되어 있으며 변경 사항은 저장 시 적용됩니다(재빌드 불필요).",
        installExtractorTitle: "지식 베이스 품질 팩 (Docling)",
        installExtractorDesc: "OCR, 표 구조 인식, 다국어 지원이 포함된 레이아웃 인식 PDF 추출기. 약 3 GB의 별도 컨테이너가 추가되며 라이브러리 가져오기에 사용됩니다.",
        installExtractorEnable: "지식 베이스 품질 팩 설치",
        installExtractorLangsLabel: "OCR 언어 (RapidOCR; 기본값은 동아시아 + 영어)",
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
        actionBuildPrivacy: "프라이버시 빌드",
        actionBuildExtractor: "추출기 빌드",
        actionJupyterTitle: "JupyterLab",
        actionOpenJupyter: "JupyterLab 열기",
        actionStopJupyter: "JupyterLab 중지",
        actionDocDBTitle: "문서 데이터베이스",
        actionImportDB: "가져오기",
        actionExportDB: "내보내기",
        actionNote: "작업을 실행하면 저장되지 않은 설정을 저장하고 이 창을 닫습니다. 진행 상황은 메인 창에 표시됩니다."
      },
      keyCheck: {
        check: "확인",
        checking: "확인 중…",
        checkHint: "이 칸의 키를 이 칸의 제공자에게 보내 확인합니다",
        heading: "이 제공자의 기본 모델 (앱이 자체 모델을 지정할 수 있음)",
        envSource: "{name}에서 지정",
        defaultsUnavailable: "기본 모델 목록을 읽을 수 없습니다.",
        status: {
          accepted: "키가 승인되었습니다",
          rejected: "제공자가 키를 거부했습니다",
          forbidden: "이 키로는 확인할 수 없습니다(권한 또는 제한). 키 자체는 유효할 수 있습니다",
          rateLimited: "요청 한도에 도달했습니다. 잠시 후 다시 시도하세요",
          serviceError: "제공자에서 오류가 발생했습니다. 잠시 후 다시 시도하세요",
          timeout: "제한 시간 내에 응답이 없습니다",
          unreachable: "제공자에 연결할 수 없습니다",
          unexpected: "제공자의 응답을 읽을 수 없습니다",
          invalidInput: "먼저 키를 입력하세요",
          opFailed: "1Password에서 키를 읽을 수 없습니다",
          busy: "확인 중입니다",
          unsupported: "이 키는 확인할 수 없습니다"
        },
        result: {
          listed: "이 키의 목록에 있음",
          notListed: "이 키의 목록에 없음",
          notCheckable: "목록에 표시되지 않음",
          unknown: "알 수 없음"
        },
        op: {
          opMissing: "1Password CLI를 찾을 수 없습니다",
          notSignedIn: "로그인하지 않았습니다",
          cancelled: "취소됨",
          notFound: "참조를 찾을 수 없음",
          timeout: "시간 초과",
          failed: "실패"
        },
        categories: {
          chat: "대화",
          code: "코드",
          vision: "이미지 이해",
          image: "이미지 생성",
          video: "동영상",
          tts: "음성 합성",
          audio_transcription: "전사",
          music: "음악"
        }
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
        ttsDictPath: "Ruta del Archivo de Diccionario TTS",
        ttsDictPathDesc: "Archivo CSV para personalizar la pronunciación. Mapea palabras/frases a deletreos fonéticos para mejorar la salida TTS.",
        selectFile: "Seleccionar Archivo",
        autoTtsMaxBytes: "Bytes Máximos de TTS Automático",
        autoTtsMaxBytesDesc: "Tamaño máximo de texto (en bytes) para TTS automático en modo posterior a la finalización. El texto que exceda este límite se reproducirá parcialmente o se omitirá. Rango: 500-10000 bytes.",
        browserMode: "Modo de Navegador",
        browserModeDesc: "Interno usa WebView integrado. Externo abre en el navegador predeterminado del sistema.",
        internalBrowser: "Navegador Interno",
        externalBrowser: "Navegador Externo",
        extraLogging: "Registro Adicional",
        aiSources: "Fuentes que la IA puede usar",
        libraryInChats: "La biblioteca, en las conversaciones",
        libraryInChatsDesc: "Activado, la IA consulta la biblioteca cuando lo pides o cuando claramente ayuda, y lo que lee se muestra en la pantalla de trabajo. Se aplica al volver a iniciar Monadic Chat.",
        extraLoggingDesc: "Habilita el registro de depuración detallado para solución de problemas. Los registros se guardan en ~/monadic/log/extra.log.",
        enableMcpServer: "Habilitar Servidor MCP",
        enableMcpServerDesc: "Habilita el servidor Model Context Protocol para integración de herramientas externas (p. ej., Claude Desktop, VS Code).",
        mcpServerPort: "Puerto del Servidor MCP",
        mcpServerPortDesc: "Puerto de red para el servidor MCP. Cambie solo si el puerto 3100 entra en conflicto con otro servicio.",
        openAtLogin: "Iniciar al iniciar sesión",
        openAtLoginDesc: "Inicia automáticamente Monadic Chat cuando inicias sesión en tu computadora.",
        menuBarMode: "Modo Barra de Menú",
        menuBarModeDesc: "Oculta el icono del Dock y ejecuta como aplicación de barra de menú. (solo macOS)",
        backgroundReplyNotifications: "Notificar cuando llegue una respuesta en segundo plano",
        backgroundReplyNotificationsDesc: "Al cerrar la Web UI, se oculta y la respuesta en curso se sigue recibiendo. Se muestra una notificación cuando llega.",
        version: "Versión",
        checkForUpdates: "Buscar Actualizaciones",
        developer: "Desarrollador",
        homepage: "Página principal",
        sourceCode: "Código fuente",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Requerido para Concept Visualizer",
        installLatexItem: "Instalar LaTeX (conjunto mínimo para diagramas)",
        installPythonTitle: "Librerías de Python (CPU)",
        installPythonDesc: "Librerías instaladas con pip para el entorno de Python. No incluye modelos/datos.",
        installMusicTitle: "Análisis musical",
        installMusicDesc: "Requerido para Music Tutor y Music Analyst. Instala bibliotecas de análisis de audio (detección de acordes, estimación de tempo/tonalidad, etc.).",
        installToolsTitle: "Herramientas del sistema (CLI)",
        installToolsDesc: "Herramientas de línea de comandos a nivel del sistema, disponibles globalmente.",
        installPrivacyTitle: "Detector de nombres — Idiomas adicionales",
        installPrivacyDesc: "El inglés siempre está habilitado. Active idiomas adicionales para encontrar nombres que ocultar en mensajes en otros idiomas. Todos los modelos de idioma están preinstalados en el contenedor Privacy; los cambios se aplican al guardar, sin reconstruir.",
        installExtractorTitle: "Pack de Calidad para Knowledge Base (Docling)",
        installExtractorDesc: "Extracción de PDF con reconocimiento de diseño, OCR, estructura de tablas y soporte multilingüe. Añade un contenedor independiente de ~3 GB; las importaciones de Library lo usan cuando está instalado.",
        installExtractorEnable: "Instalar Pack de Calidad para Knowledge Base",
        installExtractorLangsLabel: "Idiomas OCR (RapidOCR; el valor predeterminado cubre Asia Oriental + inglés)",
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
        actionBuildPrivacy: "Construir Privacidad",
        actionBuildExtractor: "Construir Extractor",
        actionJupyterTitle: "JupyterLab",
        actionOpenJupyter: "Abrir JupyterLab",
        actionStopJupyter: "Detener JupyterLab",
        actionDocDBTitle: "Base de datos de documentos",
        actionImportDB: "Importar",
        actionExportDB: "Exportar",
        actionNote: "Ejecutar una acción guardará la configuración no guardada y cerrará esta ventana. El progreso se mostrará en la ventana principal."
      },
      keyCheck: {
        check: "Comprobar",
        checking: "Comprobando…",
        checkHint: "Envía la clave de este campo al proveedor de este campo",
        heading: "Modelos predeterminados de este proveedor (las apps pueden indicar el suyo)",
        envSource: "definido en {name}",
        defaultsUnavailable: "No se pudo leer la lista de modelos predeterminados.",
        status: {
          accepted: "Clave aceptada",
          rejected: "El proveedor rechazó la clave",
          forbidden: "Esta clave no puede usar la comprobación (sin permiso o restringida); puede seguir siendo válida",
          rateLimited: "Límite de solicitudes alcanzado; inténtelo más tarde",
          serviceError: "El proveedor tuvo un error; inténtelo más tarde",
          timeout: "Sin respuesta a tiempo",
          unreachable: "No se pudo conectar con el proveedor",
          unexpected: "No se pudo leer la respuesta del proveedor",
          invalidInput: "Introduzca primero una clave",
          opFailed: "No se pudo leer la clave de 1Password",
          busy: "Ya se está comprobando",
          unsupported: "Esta clave no se puede comprobar"
        },
        result: {
          listed: "En la lista de esta clave",
          notListed: "No está en la lista de esta clave",
          notCheckable: "No aparece en la lista",
          unknown: "Desconocido"
        },
        op: {
          opMissing: "No se encontró 1Password CLI",
          notSignedIn: "sin sesión iniciada",
          cancelled: "cancelado",
          notFound: "referencia no encontrada",
          timeout: "tiempo agotado",
          failed: "error"
        },
        categories: {
          chat: "Chat",
          code: "Código",
          vision: "Visión",
          image: "Imagen",
          video: "Vídeo",
          tts: "Voz",
          audio_transcription: "Transcripción",
          music: "Música"
        }
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
        ttsDictPath: "Chemin du Fichier Dictionnaire TTS",
        ttsDictPathDesc: "Fichier CSV pour personnaliser la prononciation. Mappe les mots/phrases aux orthographes phonétiques pour améliorer la sortie TTS.",
        selectFile: "Sélectionner Fichier",
        autoTtsMaxBytes: "Octets Maximum TTS Automatique",
        autoTtsMaxBytesDesc: "Taille maximale du texte (en octets) pour le TTS automatique en mode post-achèvement. Le texte dépassant cette limite sera partiellement lu ou ignoré. Plage : 500-10000 octets.",
        browserMode: "Mode Navigateur",
        browserModeDesc: "Interne utilise WebView intégré. Externe s'ouvre dans le navigateur système par défaut.",
        internalBrowser: "Navigateur Interne",
        externalBrowser: "Navigateur Externe",
        extraLogging: "Journalisation Supplémentaire",
        aiSources: "Sources que l'IA peut utiliser",
        libraryInChats: "La bibliothèque, dans les conversations",
        libraryInChatsDesc: "Activé, l'IA consulte la bibliothèque quand vous le demandez ou quand cela aide clairement, et ce qu'elle lit s'affiche sur l'écran de travail. Prend effet au prochain démarrage de Monadic Chat.",
        extraLoggingDesc: "Active la journalisation de débogage détaillée pour le dépannage. Les journaux sont enregistrés dans ~/monadic/log/extra.log.",
        enableMcpServer: "Activer le Serveur MCP",
        enableMcpServerDesc: "Active le serveur Model Context Protocol pour l'intégration d'outils externes (par ex., Claude Desktop, VS Code).",
        mcpServerPort: "Port du Serveur MCP",
        mcpServerPortDesc: "Port réseau pour le serveur MCP. Ne modifiez que si le port 3100 entre en conflit avec un autre service.",
        openAtLogin: "Lancer au démarrage",
        openAtLoginDesc: "Démarre automatiquement Monadic Chat lorsque vous vous connectez à votre ordinateur.",
        menuBarMode: "Mode Barre de Menu",
        menuBarModeDesc: "Masque l'icône du Dock et s'exécute comme application de barre de menu. (macOS uniquement)",
        backgroundReplyNotifications: "Notifier quand une réponse arrive en arrière-plan",
        backgroundReplyNotificationsDesc: "Fermer la Web UI la masque, et la réponse en cours continue d'arriver. Une notification s'affiche à son arrivée.",
        version: "Version",
        checkForUpdates: "Vérifier les mises à jour",
        developer: "Développeur",
        homepage: "Page d'accueil",
        sourceCode: "Code source",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Nécessaire pour Concept Visualizer",
        installLatexItem: "Installer LaTeX (ensemble minimal pour les diagrammes)",
        installPythonTitle: "Bibliothèques Python (CPU)",
        installPythonDesc: "Bibliothèques pip pour l'environnement Python. Modèles/données non inclus.",
        installMusicTitle: "Analyse musicale",
        installMusicDesc: "Requis pour Music Tutor et Music Analyst. Installe les bibliothèques d'analyse audio (détection d'accords, estimation du tempo/tonalité, etc.).",
        installToolsTitle: "Outils système (CLI)",
        installToolsDesc: "Outils en ligne de commande au niveau du système, disponibles globalement.",
        installPrivacyTitle: "Détecteur de noms — Langues supplémentaires",
        installPrivacyDesc: "L'anglais est toujours activé. Activez des langues supplémentaires pour trouver les noms à masquer dans les messages en d'autres langues. Tous les modèles de langue sont préinstallés dans le conteneur Privacy ; les modifications s'appliquent à l'enregistrement, sans reconstruction.",
        installExtractorTitle: "Pack de qualité Knowledge Base (Docling)",
        installExtractorDesc: "Extraction de PDF avec reconnaissance de mise en page, OCR, structure des tableaux et support multilingue. Ajoute un conteneur séparé d'environ 3 Go ; les imports Library l'utilisent une fois installé.",
        installExtractorEnable: "Installer le Pack de qualité Knowledge Base",
        installExtractorLangsLabel: "Langues OCR (RapidOCR ; par défaut couvre l'Asie de l'Est + anglais)",
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
        actionBuildPrivacy: "Construire Privacy",
        actionBuildExtractor: "Construire Extractor",
        actionJupyterTitle: "JupyterLab",
        actionOpenJupyter: "Ouvrir JupyterLab",
        actionStopJupyter: "Arrêter JupyterLab",
        actionDocDBTitle: "Base de données de documents",
        actionImportDB: "Importer",
        actionExportDB: "Exporter",
        actionNote: "L'exécution d'une action enregistrera les paramètres non sauvegardés et fermera cette fenêtre. La progression sera affichée dans la fenêtre principale."
      },
      keyCheck: {
        check: "Vérifier",
        checking: "Vérification…",
        checkHint: "Envoie la clé de ce champ au fournisseur de ce champ",
        heading: "Modèles par défaut de ce fournisseur (les apps peuvent indiquer le leur)",
        envSource: "défini par {name}",
        defaultsUnavailable: "Impossible de lire la liste des modèles par défaut.",
        status: {
          accepted: "Clé acceptée",
          rejected: "Le fournisseur a refusé la clé",
          forbidden: "Cette clé ne peut pas utiliser la vérification (droits ou restriction) ; elle peut rester valide",
          rateLimited: "Limite de requêtes atteinte ; réessayez plus tard",
          serviceError: "Le fournisseur a rencontré une erreur ; réessayez plus tard",
          timeout: "Pas de réponse à temps",
          unreachable: "Impossible de joindre le fournisseur",
          unexpected: "Impossible de lire la réponse du fournisseur",
          invalidInput: "Saisissez d'abord une clé",
          opFailed: "Impossible de lire la clé depuis 1Password",
          busy: "Vérification déjà en cours",
          unsupported: "Cette clé ne peut pas être vérifiée"
        },
        result: {
          listed: "Dans la liste de cette clé",
          notListed: "Absent de la liste de cette clé",
          notCheckable: "Non affiché dans la liste",
          unknown: "Inconnu"
        },
        op: {
          opMissing: "1Password CLI introuvable",
          notSignedIn: "non connecté",
          cancelled: "annulé",
          notFound: "référence introuvable",
          timeout: "délai dépassé",
          failed: "échec"
        },
        categories: {
          chat: "Chat",
          code: "Code",
          vision: "Vision",
          image: "Image",
          video: "Vidéo",
          tts: "Synthèse vocale",
          audio_transcription: "Transcription",
          music: "Musique"
        }
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
        ttsDictPath: "TTS-Wörterbuchdateipfad",
        ttsDictPathDesc: "CSV-Datei zur Anpassung der Aussprache. Ordnet Wörter/Phrasen phonetischen Schreibweisen zu, um die TTS-Ausgabe zu verbessern.",
        selectFile: "Datei auswählen",
        autoTtsMaxBytes: "Automatische TTS Maximale Bytes",
        autoTtsMaxBytesDesc: "Maximale Textgröße (in Bytes) für automatisches TTS im Nachvervollständigungsmodus. Text, der dieses Limit überschreitet, wird teilweise abgespielt oder übersprungen. Bereich: 500-10000 Bytes.",
        browserMode: "Browser-Modus",
        browserModeDesc: "Intern verwendet integrierten WebView. Extern öffnet im Standard-Systembrowser.",
        internalBrowser: "Interner Browser",
        externalBrowser: "Externer Browser",
        extraLogging: "Zusätzliche Protokollierung",
        aiSources: "Quellen, die die KI nutzen kann",
        libraryInChats: "Die Bibliothek, in Gesprächen",
        libraryInChatsDesc: "Wenn aktiviert, zieht die KI die Bibliothek heran, wenn Sie darum bitten oder es deutlich hilft, und das Gelesene wird auf dem Arbeitsbildschirm angezeigt. Wird beim nächsten Start von Monadic Chat wirksam.",
        extraLoggingDesc: "Aktiviert detaillierte Debug-Protokollierung zur Fehlerbehebung. Protokolle werden in ~/monadic/log/extra.log gespeichert.",
        enableMcpServer: "MCP-Server aktivieren",
        enableMcpServerDesc: "Aktiviert den Model Context Protocol-Server für externe Tool-Integration (z. B. Claude Desktop, VS Code).",
        mcpServerPort: "MCP-Server-Port",
        mcpServerPortDesc: "Netzwerkport für MCP-Server. Ändern Sie nur, wenn Port 3100 mit einem anderen Dienst in Konflikt steht.",
        openAtLogin: "Bei Anmeldung starten",
        openAtLoginDesc: "Startet Monadic Chat automatisch, wenn Sie sich an Ihrem Computer anmelden.",
        menuBarMode: "Menüleisten-Modus",
        menuBarModeDesc: "Blendet das Dock-Symbol aus und führt die App als Menüleisten-App aus. (nur macOS)",
        backgroundReplyNotifications: "Benachrichtigen, wenn eine Antwort im Hintergrund eintrifft",
        backgroundReplyNotificationsDesc: "Wird die Web UI geschlossen, wird sie verborgen, und eine laufende Antwort kommt weiter an. Bei ihrem Eintreffen erscheint eine Benachrichtigung.",
        version: "Version",
        checkForUpdates: "Nach Updates suchen",
        developer: "Entwickler",
        homepage: "Startseite",
        sourceCode: "Quellcode",
        installLatexTitle: "LaTeX",
        installLatexDesc: "Erforderlich für Concept Visualizer",
        installLatexItem: "LaTeX installieren (Minimalsatz für Diagramme)",
        installPythonTitle: "Python-Bibliotheken (CPU)",
        installPythonDesc: "Per pip installierte Bibliotheken für die Python-Laufzeit. Modelle/Datasets sind nicht enthalten.",
        installMusicTitle: "Musikanalyse",
        installMusicDesc: "Erforderlich für Music Tutor und Music Analyst. Installiert Audioanalyse-Bibliotheken (Akkorderkennung, Tempo-/Tonarterkennung usw.).",
        installToolsTitle: "Systemwerkzeuge (CLI)",
        installToolsDesc: "Befehlszeilenwerkzeuge auf Betriebssystemebene, systemweit verfügbar.",
        installPrivacyTitle: "Namenserkennung — Zusätzliche Sprachen",
        installPrivacyDesc: "Englisch ist immer aktiviert. Aktivieren Sie weitere Sprachen, um in Nachrichten in anderen Sprachen Namen zum Verbergen zu finden. Alle Sprachmodelle sind im Privacy-Container vorinstalliert; Änderungen gelten beim Speichern, ohne Neuaufbau.",
        installExtractorTitle: "Knowledge Base Quality Pack (Docling)",
        installExtractorDesc: "Layout-bewusste PDF-Extraktion mit OCR, Tabellenstruktur und mehrsprachiger Unterstützung. Fügt einen separaten Container von ~3 GB hinzu; Library-Importe nutzen ihn, sobald installiert.",
        installExtractorEnable: "Knowledge Base Quality Pack installieren",
        installExtractorLangsLabel: "OCR-Sprachen (RapidOCR; Standard deckt Ostasien + Englisch ab)",
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
        actionBuildPrivacy: "Privacy erstellen",
        actionBuildExtractor: "Extractor erstellen",
        actionJupyterTitle: "JupyterLab",
        actionOpenJupyter: "JupyterLab öffnen",
        actionStopJupyter: "JupyterLab stoppen",
        actionDocDBTitle: "Dokumentendatenbank",
        actionImportDB: "Importieren",
        actionExportDB: "Exportieren",
        actionNote: "Das Ausführen einer Aktion speichert nicht gespeicherte Einstellungen und schließt dieses Fenster. Der Fortschritt wird im Hauptfenster angezeigt."
      },
      keyCheck: {
        check: "Prüfen",
        checking: "Wird geprüft…",
        checkHint: "Sendet den Schlüssel in diesem Feld an den Anbieter dieses Felds",
        heading: "Standardmodelle dieses Anbieters (Apps können ein eigenes angeben)",
        envSource: "gesetzt durch {name}",
        defaultsUnavailable: "Die Liste der Standardmodelle konnte nicht gelesen werden.",
        status: {
          accepted: "Schlüssel akzeptiert",
          rejected: "Der Anbieter hat den Schlüssel abgelehnt",
          forbidden: "Dieser Schlüssel kann die Prüfung nicht verwenden (keine Berechtigung oder Einschränkung); er kann trotzdem gültig sein",
          rateLimited: "Anfragelimit erreicht; später erneut versuchen",
          serviceError: "Fehler beim Anbieter; später erneut versuchen",
          timeout: "Keine Antwort in der Zeit",
          unreachable: "Anbieter nicht erreichbar",
          unexpected: "Die Antwort des Anbieters konnte nicht gelesen werden",
          invalidInput: "Zuerst einen Schlüssel eingeben",
          opFailed: "Schlüssel konnte nicht aus 1Password gelesen werden",
          busy: "Wird bereits geprüft",
          unsupported: "Dieser Schlüssel kann nicht geprüft werden"
        },
        result: {
          listed: "In der Liste dieses Schlüssels",
          notListed: "Nicht in der Liste dieses Schlüssels",
          notCheckable: "Nicht in der Liste aufgeführt",
          unknown: "Unbekannt"
        },
        op: {
          opMissing: "1Password CLI nicht gefunden",
          notSignedIn: "nicht angemeldet",
          cancelled: "abgebrochen",
          notFound: "Referenz nicht gefunden",
          timeout: "Zeitüberschreitung",
          failed: "fehlgeschlagen"
        },
        categories: {
          chat: "Chat",
          code: "Code",
          vision: "Bildverständnis",
          image: "Bild",
          video: "Video",
          tts: "Sprachausgabe",
          audio_transcription: "Transkription",
          music: "Musik"
        }
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
