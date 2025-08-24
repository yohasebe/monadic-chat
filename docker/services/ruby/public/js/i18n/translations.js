// Web UI Translations
const webUITranslations = {
  en: {
    ui: {
      start: "Start",
      stop: "Stop",
      restart: "Restart",
      rebuild: "Rebuild",
      update: "Update",
      openBrowser: "Browser",
      sharedFolder: "Shared",
      quit: "Quit",
      mode: "Mode",
      docker: "Docker",
      system: "System",
      send: "Send",
      clear: "Clear",
      voice: "Voice",
      settings: "Settings",
      run: "Run",
      version: "Version",
      conversationLanguage: "Conversation Language",
      voiceChatControls: "Voice Chat Interaction Controls",
      currentBaseApp: "Current Base App",
      selectApp: "Select App",
      searchApps: "Search apps...",
      availableApps: "Available Apps",
      notStarted: "Not started",
      notSelected: "Not selected",
      notConfigured: "Not configured",
      noDataAvailable: "No data available",
      reset: "Reset",
      import: "Import",
      export: "Export",
      homepage: "Homepage",
      cancelQuery: "Cancel Query",
      toggleMenu: "Toggle Menu",
      status: "Status",
      mode: "Mode",
      standalone: "Standalone",
      server: "Server",
      network: "Network",
      textToSpeechProvider: "Text-to-Speech Provider",
      speechToTextProvider: "Speech-to-Text Provider",
      elevenLabsVoice: "Elevenlabs Text-to-Speech Voice",
      openAIVoice: "OpenAI Text-to-Speech Voice",
      geminiVoice: "Gemini Text-to-Speech Voice",
      voiceSettings: "Voice Settings",
      appSettings: "App Settings",
      conversationControl: "Conversation Control",
      image: "Image",
      fromFile: "From file",
      fromURL: "From URL",
      speechInput: "Speech Input",
      importFile: "Import File",
      attachImage: "Attach image file to message",
      importFromDoc: "Import text from document file",
      importFromWeb: "Import text from web URL",
      startStopVoice: "Start/stop voice input recording",
      monadicChatInfo: "Monadic Chat Info",
      monadicChatStatus: "Monadic Chat Status",
      aiAssistantAndUser: "AI Assistant & AI User",
      github: "GitHub",
      version: "Version",
      pdfDatabase: "PDF Database",
      sessionLabel: "Session",
      speech: "Speech",
      systemSettings: "System Settings",
      baseApp: "Base App",
      maxContextSize: "Max Context Size",
      maxOutputTokens: "Max Output Tokens",
      model: "Model",
      reasoningEffort: "Reasoning Effort",
      pdfToDb: "PDF → DB",
      temperature: "Temperature",
      presencePenalty: "Presence Penalty",
      frequencyPenalty: "Frequency Penalty",
      showInitialPromptAssistant: "Show Initial Prompt for Assistant",
      promptCaching: "Prompt Caching",
      webSearch: "Web Search",
      showInitialPromptAIUser: "Show Initial Prompt for AI-User",
      startFromAssistant: "Start from assistant",
      mathRendering: "Math Rendering",
      autoSpeech: "Auto speech",
      easySubmit: "Easy submit",
      easySubmitHint: "(with Enter key or Stop button)",
      autoScroll: "Auto scroll while streaming",
      webSpeechVoice: "Web Speech API Voice",
      ttsSpeed: "TTS Speed",
      statistics: "Statistics",
      clickToToggle: "click to toggle",
      tokensInSystemPrompts: "Tokens in all system prompts",
      tokensInUserMessages: "Tokens in all user messages",
      tokensInAssistantMessages: "Tokens in all assistant messages",
      tokensInActiveMessages: "Tokens in all active messages",
      tokensInAllMessages: "Tokens in all messages",
      numberOfAllMessages: "Number of all messages",
      numberOfActiveMessages: "Number of active messages",
      voiceChatOperationControl: "Voice Chat Operation Control",
      dialog: "Dialog",
      user: "User",
      assistant: "Assistant",
      aiAssistant: "AI Assistant",
      aiUser: "AI User",
      generateAIUserResponse: "Generate AI user response based on conversation",
      generateAIUserResponsePerplexity: "Generate AI user response (Perplexity requires alternating user/assistant messages)",
      role: "Role",
      roleOptions: {
        user: "User",
        sampleUser: "User (to add to past messages)",
        sampleAssistant: "Assistant (to add to past messages)",
        sampleSystem: "System (to provide additional direction)"
      },
      messagePlaceholder: "Type your message or click Speech Input button to use voice . . .",
      pressToSend: "Press Send button to send your message.",
      resetDescription: "Press \"reset\" to clear conversation while keeping the current app selection.",
      imagePdf: "Image/PDF",
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
        connecting: "Connecting...",
        readyForInput: "Ready for input",
        responding: "RESPONDING",
        responseReceived: "Response received",
        readyToStart: "Ready to start",
        verifyingToken: "Verifying token",
        operationTimedOut: "Operation timed out. UI reset.",
        languageChanged: "Language changed to",
        webSpeechNotAvailable: "Web Speech API not available in this browser",
        generatingAIUserResponse: "Generating AI user response...",
        aiUserResponseGenerated: "AI user response generated",
        generatingResponse: "Generating response from assistant...",
        operationCanceled: "Operation canceled",
        thinking: "THINKING",
        spinnerStarting: "Starting",
        spinnerCallingFunctions: "Calling functions",
        spinnerReceivingResponse: "Receiving response",
        spinnerGeneratingAIUser: "Generating AI user response",
        spinnerSearchingWeb: "Searching web",
        spinnerProcessing: "Processing",
        spinnerProcessingRequest: "Processing request",
        spinnerProcessingTools: "Processing tools",
        spinnerListening: "Listening...",
        spinnerProcessingSpeech: "Processing speech...",
        thinkingProcess: "Thinking Process",
        reasoningProcess: "Reasoning Process",
        processingMessage: "Processing sample message",
        sampleTimeout: "Sample message timed out. Please try again.",
        uploadNotAvailable: "Upload functionality not available",
        uploadSuccess: "uploaded successfully",
        uploadError: "Error uploading file",
        convertError: "Error converting document",
        fetchError: "Error fetching webpage",
        selectFileImport: "Please select a file to import",
        sessionImported: "Session imported successfully",
        importError: "Error importing session",
        voiceRecognitionFinished: "Voice recognition finished",
        maskCreated: "Mask created for",
        maskRemoved: "Mask removed",
        pdfUploadError: "PDF files cannot be uploaded in image generation apps",
        connected: "Connected",
        disconnected: "Disconnected",
        connectionLost: "Connection lost",
        reconnecting: "Reconnecting...",
        noAppsAvailable: "No apps available - check API keys in settings"
      },
      session: {
        startSession: "Start Session",
        continueSession: "Continue Session"
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
      openBrowser: "ブラウザ",
      sharedFolder: "共有",
      quit: "終了",
      mode: "モード",
      docker: "Docker",
      system: "システム",
      send: "送信",
      clear: "クリア",
      voice: "音声",
      settings: "設定",
      run: "実行",
      version: "バージョン",
      conversationLanguage: "会話言語",
      voiceChatControls: "音声チャット操作コントロール",
      currentBaseApp: "現在のアプリ",
      selectApp: "アプリを選択",
      searchApps: "アプリを検索...",
      availableApps: "利用可能なアプリ",
      notStarted: "未開始",
      notSelected: "未選択",
      notConfigured: "未設定",
      noDataAvailable: "データなし",
      reset: "リセット",
      import: "インポート",
      export: "エクスポート",
      homepage: "ホームページ",
      cancelQuery: "クエリをキャンセル",
      toggleMenu: "メニュー切替",
      status: "ステータス",
      mode: "モード",
      standalone: "スタンドアロン",
      server: "サーバー",
      network: "ネットワーク",
      textToSpeechProvider: "テキスト読み上げプロバイダー",
      speechToTextProvider: "音声認識プロバイダー",
      elevenLabsVoice: "Elevenlabs 音声",
      openAIVoice: "OpenAI 音声",
      geminiVoice: "Gemini 音声",
      voiceSettings: "音声設定",
      appSettings: "アプリ設定",
      conversationControl: "会話制御",
      image: "画像",
      fromFile: "ファイルから",
      fromURL: "URLから",
      speechInput: "音声入力",
      importFile: "ファイルをインポート",
      attachImage: "メッセージに画像ファイルを添付",
      importFromDoc: "ドキュメントファイルからテキストをインポート",
      importFromWeb: "Web URLからテキストをインポート",
      startStopVoice: "音声入力の開始/停止",
      monadicChatInfo: "Monadic Chat情報",
      monadicChatStatus: "Monadic Chatステータス",
      aiAssistantAndUser: "AIアシスタント & AIユーザー",
      github: "GitHub",
      version: "バージョン",
      pdfDatabase: "PDFデータベース",
      sessionLabel: "セッション",
      speech: "音声",
      systemSettings: "システム設定",
      baseApp: "ベースアプリ",
      maxContextSize: "最大コンテキストサイズ",
      maxOutputTokens: "最大出力トークン数",
      model: "モデル",
      reasoningEffort: "推論努力",
      pdfToDb: "PDF → DB",
      temperature: "温度",
      presencePenalty: "存在ペナルティ",
      frequencyPenalty: "频度ペナルティ",
      showInitialPromptAssistant: "アシスタントの初期プロンプトを表示",
      promptCaching: "プロンプトキャッシング",
      webSearch: "ウェブ検索",
      showInitialPromptAIUser: "AIユーザーの初期プロンプトを表示",
      startFromAssistant: "アシスタントから開始",
      mathRendering: "数式レンダリング",
      autoSpeech: "自動音声",
      easySubmit: "簡単送信",
      easySubmitHint: "（Enterキーまたは停止ボタンで）",
      autoScroll: "ストリーミング中の自動スクロール",
      webSpeechVoice: "Web Speech API音声",
      ttsSpeed: "TTS速度",
      statistics: "統計",
      clickToToggle: "クリックで切り替え",
      tokensInSystemPrompts: "すべてのシステムプロンプトのトークン数",
      tokensInUserMessages: "すべてのユーザーメッセージのトークン数",
      tokensInAssistantMessages: "すべてのアシスタントメッセージのトークン数",
      tokensInActiveMessages: "すべてのアクティブメッセージのトークン数",
      tokensInAllMessages: "すべてのメッセージのトークン数",
      numberOfAllMessages: "すべてのメッセージ数",
      numberOfActiveMessages: "アクティブメッセージ数",
      voiceChatOperationControl: "音声チャット操作コントロール",
      dialog: "ダイアログ",
      user: "ユーザー",
      assistant: "アシスタント",
      aiAssistant: "AIアシスタント",
      aiUser: "AIユーザー",
      generateAIUserResponse: "会話に基づいてAIユーザー応答を生成",
      generateAIUserResponsePerplexity: "AIユーザー応答を生成（Perplexityはユーザー/アシスタントの交互メッセージが必要）",
      role: "役割",
      roleOptions: {
        user: "ユーザー",
        sampleUser: "ユーザー（過去のメッセージに追加）",
        sampleAssistant: "アシスタント（過去のメッセージに追加）",
        sampleSystem: "システム（追加の指示を提供）"
      },
      messagePlaceholder: "メッセージを入力するか、音声入力ボタンをクリックして音声を使用してください...",
      pressToSend: "送信ボタンを押してメッセージを送信してください。",
      resetDescription: "「リセット」を押すと、現在のアプリ選択を維持したまま会話をクリアします。",
      imagePdf: "画像/PDF",
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
        connecting: "接続中...",
        readyForInput: "入力可能",
        responding: "応答中",
        responseReceived: "応答受信完了",
        readyToStart: "開始準備完了",
        verifyingToken: "トークンを検証中",
        operationTimedOut: "操作がタイムアウトしました。UIをリセットしました。",
        languageChanged: "言語を変更しました：",
        webSpeechNotAvailable: "このブラウザでは音声認識APIが利用できません",
        generatingAIUserResponse: "AIユーザー応答を生成中...",
        aiUserResponseGenerated: "AIユーザー応答が生成されました",
        generatingResponse: "アシスタントからの応答を生成中...",
        operationCanceled: "操作がキャンセルされました",
        thinking: "思考中",
        spinnerStarting: "開始中",
        spinnerCallingFunctions: "関数呼び出し中",
        spinnerReceivingResponse: "応答受信中",
        spinnerGeneratingAIUser: "AIユーザー応答生成中",
        spinnerSearchingWeb: "ウェブ検索中",
        spinnerProcessing: "処理中",
        spinnerProcessingRequest: "リクエスト処理中",
        spinnerProcessingTools: "ツール処理中",
        spinnerListening: "リスニング中...",
        spinnerProcessingSpeech: "音声処理中...",
        thinkingProcess: "思考プロセス",
        reasoningProcess: "推論プロセス",
        processingMessage: "サンプルメッセージを処理中",
        sampleTimeout: "サンプルメッセージがタイムアウトしました。もう一度お試しください。",
        uploadNotAvailable: "アップロード機能は利用できません",
        uploadSuccess: "が正常にアップロードされました",
        uploadError: "ファイルのアップロードエラー",
        convertError: "ドキュメントの変換エラー",
        fetchError: "ウェブページの取得エラー",
        selectFileImport: "インポートするファイルを選択してください",
        sessionImported: "セッションが正常にインポートされました",
        importError: "セッションのインポートエラー",
        voiceRecognitionFinished: "音声認識が完了しました",
        maskCreated: "マスクが作成されました：",
        maskRemoved: "マスクが削除されました",
        pdfUploadError: "画像生成アプリではPDFファイルをアップロードできません",
        connected: "接続済み",
        disconnected: "切断",
        connectionLost: "接続が失われました",
        reconnecting: "再接続中...",
        noAppsAvailable: "利用可能なアプリがありません - 設定でAPIキーを確認してください"
      },
      session: {
        startSession: "セッションを開始",
        continueSession: "セッションを続行"
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
      openBrowser: "浏览器",
      sharedFolder: "共享",
      quit: "退出",
      send: "发送",
      clear: "清除",
      voice: "语音",
      settings: "设置",
      run: "运行",
      version: "版本",
      conversationLanguage: "对话语言",
      voiceChatControls: "语音聊天交互控制",
      voiceChatOperationControl: "语音聊天操作控制",
      statistics: "统计",
      clickToToggle: "点击切换",
      tokensInSystemPrompts: "所有系统提示的令牌数",
      tokensInUserMessages: "所有用户消息的令牌数",
      tokensInAssistantMessages: "所有助手消息的令牌数",
      tokensInActiveMessages: "所有活动消息的令牌数",
      tokensInAllMessages: "所有消息的令牌数",
      numberOfAllMessages: "所有消息数",
      numberOfActiveMessages: "活动消息数",
      dialog: "对话",
      user: "用户",
      assistant: "助手",
      aiAssistant: "AI助手",
      aiUser: "AI用户",
      generateAIUserResponse: "基于对话生成AI用户响应",
      generateAIUserResponsePerplexity: "生成AI用户响应（Perplexity需要交替的用户/助手消息）",
      role: "角色",
      roleOptions: {
        user: "用户",
        sampleUser: "用户（添加到过去的消息）",
        sampleAssistant: "助手（添加到过去的消息）",
        sampleSystem: "系统（提供额外指示）"
      },
      messagePlaceholder: "输入消息或点击语音输入按钮使用语音...",
      pressToSend: "按发送按钮发送消息。",
      resetDescription: "按\"重置\"清除对话，同时保持当前的应用程序选择。",
      imagePdf: "图像/PDF",
      maxContextSize: "最大上下文大小",
      maxOutputTokens: "最大输出令牌数",
      model: "模型",
      reasoningEffort: "推理努力",
      pdfToDb: "PDF → 数据库",
      temperature: "温度",
      presencePenalty: "存在惩罚",
      frequencyPenalty: "频率惩罚",
      showInitialPromptAssistant: "显示助手初始提示",
      promptCaching: "提示缓存",
      webSearch: "网络搜索",
      showInitialPromptAIUser: "显示AI用户初始提示",
      startFromAssistant: "从助手开始",
      mathRendering: "数学渲染",
      autoSpeech: "自动语音",
      easySubmit: "轻松提交",
      easySubmitHint: "（使用回车键或停止按钮）",
      autoScroll: "流式传输时自动滚动",
      webSpeechVoice: "Web Speech API语音",
      ttsSpeed: "TTS速度",
      baseApp: "基础应用",
      systemSettings: "系统设置",
      speech: "语音",
      sessionLabel: "会话",
      pdfDatabase: "PDF数据库",
      monadicChatInfo: "Monadic Chat信息",
      monadicChatStatus: "Monadic Chat状态",
      aiAssistantAndUser: "AI助手 & AI用户",
      github: "GitHub",
      version: "版本",
      currentBaseApp: "当前应用",
      selectApp: "选择应用",
      searchApps: "搜索应用...",
      availableApps: "可用应用",
      notStarted: "未启动",
      notSelected: "未选择",
      notConfigured: "未配置",
      noDataAvailable: "无数据",
      reset: "重置",
      import: "导入",
      export: "导出",
      homepage: "主页",
      cancelQuery: "取消查询",
      toggleMenu: "切换菜单",
      status: "状态",
      mode: "模式",
      standalone: "单机",
      server: "服务器",
      network: "网络",
      textToSpeechProvider: "文本转语音提供商",
      speechToTextProvider: "语音转文本提供商",
      elevenLabsVoice: "Elevenlabs 语音",
      openAIVoice: "OpenAI 语音",
      geminiVoice: "Gemini 语音",
      voiceSettings: "语音设置",
      appSettings: "应用设置",
      conversationControl: "对话控制",
      image: "图像",
      fromFile: "从文件",
      fromURL: "从URL",
      speechInput: "语音输入",
      importFile: "导入文件",
      attachImage: "将图像文件附加到消息",
      importFromDoc: "从文档文件导入文本",
      importFromWeb: "从Web URL导入文本",
      startStopVoice: "开始/停止语音输入",
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
        connecting: "连接中...",
        readyForInput: "准备输入",
        responding: "响应中",
        responseReceived: "响应接收完成",
        readyToStart: "准备开始",
        verifyingToken: "验证令牌中",
        operationTimedOut: "操作超时。UI已重置。",
        languageChanged: "语言已更改为",
        webSpeechNotAvailable: "此浏览器不支持语音识别API",
        generatingAIUserResponse: "正在生成AI用户响应...",
        aiUserResponseGenerated: "AI用户响应已生成",
        generatingResponse: "正在生成助手响应...",
        operationCanceled: "操作已取消",
        thinking: "思考中",
        spinnerStarting: "启动中",
        spinnerCallingFunctions: "调用函数中",
        spinnerReceivingResponse: "接收响应中",
        spinnerGeneratingAIUser: "生成AI用户响应",
        spinnerSearchingWeb: "搜索网络",
        spinnerProcessing: "处理中",
        spinnerProcessingRequest: "处理请求中",
        spinnerProcessingTools: "处理工具中",
        spinnerListening: "正在倾听...",
        spinnerProcessingSpeech: "处理语音中...",
        thinkingProcess: "思考过程",
        reasoningProcess: "推理过程",
        processingMessage: "正在处理示例消息",
        sampleTimeout: "示例消息超时。请重试。",
        clickToEnableAudio: "点击任意位置启用音频",
        clickToEnableAudioSimple: "点击启用音频",
        tapToEnableIOSAudio: "点击启用iOS音频",
        cannotConnectToAPI: "无法连接到OpenAI API",
        validTokenNotSet: "未设置有效的OpenAI令牌",
        pleaseWait: "请稍候",
        voiceRecognitionFinished: "语音识别完成",
        noAppsAvailable: "没有可用的应用程序",
        sampleMessageAdded: "已添加示例消息",
        connectionFailed: "连接失败",
        connectionFailedRefresh: "连接失败 - 请刷新页面",
        resetSuccessful: "重置成功",
        microphoneAccessError: "麦克风访问错误",
        listeningStatus: "正在倾听 . . .",
        processingStatus: "处理中 ...",
        noAudioDetected: "未检测到音频：请检查您的麦克风设置",
        audioProcessingFailed: "音频处理失败",
        silenceDetected: "检测到静音：请检查您的麦克风设置",
        pdfUploadError: "图像生成应用无法上传PDF文件",
        pdfModelRestriction: "只有使用支持PDF输入的模型时才能上传PDF文件",
        errorUploadingFile: "上传文件出错",
        maskRemoved: "遮罩已移除",
        maskEditingNotAvailable: "此应用不支持遮罩编辑",
        maskEditorNotAvailable: "遮罩编辑器不可用",
        errorProcessingImage: "处理图像出错",
        errorLoadingImage: "加载图像出错",
        errorReadingFile: "读取文件出错",
        webSocketConnectionError: "WebSocket连接错误",
        messageDeleted: "消息已删除",
        uploadNotAvailable: "上传功能不可用",
        uploadSuccess: "上传成功",
        uploadError: "文件上传错误",
        convertError: "文档转换错误",
        fetchError: "获取网页错误",
        selectFileImport: "请选择要导入的文件",
        sessionImported: "会话导入成功",
        importError: "会话导入错误",
        voiceRecognitionFinished: "语音识别完成",
        maskCreated: "已创建遮罩：",
        maskRemoved: "已移除遮罩",
        pdfUploadError: "图像生成应用中无法上传PDF文件",
        connected: "已连接",
        disconnected: "已断开",
        connectionLost: "连接丢失",
        reconnecting: "重新连接中...",
        noAppsAvailable: "没有可用的应用 - 请在设置中检查API密钥"
      },
      session: {
        startSession: "开始会话",
        continueSession: "继续会话"
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
      openBrowser: "브라우저",
      sharedFolder: "공유",
      quit: "종료",
      send: "전송",
      clear: "지우기",
      voice: "음성",
      settings: "설정",
      run: "실행",
      version: "버전",
      conversationLanguage: "대화 언어",
      voiceChatControls: "음성 채팅 상호작용 컨트롤",
      voiceChatOperationControl: "음성 채팅 조작 컨트롤",
      statistics: "통계",
      clickToToggle: "클릭하여 전환",
      tokensInSystemPrompts: "모든 시스템 프롬프트의 토큰 수",
      tokensInUserMessages: "모든 사용자 메시지의 토큰 수",
      tokensInAssistantMessages: "모든 어시스턴트 메시지의 토큰 수",
      tokensInActiveMessages: "모든 활성 메시지의 토큰 수",
      tokensInAllMessages: "모든 메시지의 토큰 수",
      numberOfAllMessages: "모든 메시지 수",
      numberOfActiveMessages: "활성 메시지 수",
      dialog: "대화",
      user: "사용자",
      assistant: "어시스턴트",
      aiAssistant: "AI 어시스턴트",
      aiUser: "AI 사용자",
      generateAIUserResponse: "대화를 기반으로 AI 사용자 응답 생성",
      generateAIUserResponsePerplexity: "AI 사용자 응답 생성 (Perplexity는 사용자/어시스턴트 교대 메시지 필요)",
      role: "역할",
      roleOptions: {
        user: "사용자",
        sampleUser: "사용자 (과거 메시지에 추가)",
        sampleAssistant: "어시스턴트 (과거 메시지에 추가)",
        sampleSystem: "시스템 (추가 지시 제공)"
      },
      messagePlaceholder: "메시지를 입력하거나 음성 입력 버튼을 클릭하여 음성을 사용하세요...",
      pressToSend: "전송 버튼을 눌러 메시지를 보냅니다.",
      resetDescription: "\"재설정\"을 누르면 현재 앱 선택을 유지하면서 대화를 지웁니다.",
      imagePdf: "이미지/PDF",
      maxContextSize: "최대 컨텍스트 크기",
      maxOutputTokens: "최대 출력 토큰 수",
      model: "모델",
      reasoningEffort: "추론 노력",
      pdfToDb: "PDF → DB",
      temperature: "온도",
      presencePenalty: "존재 페널티",
      frequencyPenalty: "빈도 페널티",
      showInitialPromptAssistant: "어시스턴트 초기 프롬프트 표시",
      promptCaching: "프롬프트 캐싱",
      webSearch: "웹 검색",
      showInitialPromptAIUser: "AI 사용자 초기 프롬프트 표시",
      startFromAssistant: "어시스턴트부터 시작",
      mathRendering: "수학 렌더링",
      autoSpeech: "자동 음성",
      easySubmit: "간편 제출",
      easySubmitHint: "（Enter 키 또는 정지 버튼으로）",
      autoScroll: "스트리밍 중 자동 스크롤",
      webSpeechVoice: "Web Speech API 음성",
      ttsSpeed: "TTS 속도",
      baseApp: "기본 앱",
      systemSettings: "시스템 설정",
      speech: "음성",
      sessionLabel: "세션",
      pdfDatabase: "PDF 데이터베이스",
      monadicChatInfo: "Monadic Chat 정보",
      monadicChatStatus: "Monadic Chat 상태",
      aiAssistantAndUser: "AI 어시스턴트 & AI 사용자",
      github: "GitHub",
      version: "버전",
      currentBaseApp: "현재 앱",
      selectApp: "앱 선택",
      searchApps: "앱 검색...",
      availableApps: "사용 가능한 앱",
      notStarted: "시작 안 됨",
      notSelected: "선택 안 됨",
      notConfigured: "구성 안 됨",
      noDataAvailable: "데이터 없음",
      reset: "재설정",
      import: "가져오기",
      export: "내보내기",
      homepage: "홈페이지",
      cancelQuery: "쿼리 취소",
      toggleMenu: "메뉴 토글",
      status: "상태",
      mode: "모드",
      standalone: "독립형",
      server: "서버",
      network: "네트워크",
      textToSpeechProvider: "텍스트 음성 변환 제공자",
      speechToTextProvider: "음성 텍스트 변환 제공자",
      elevenLabsVoice: "Elevenlabs 음성",
      openAIVoice: "OpenAI 음성",
      geminiVoice: "Gemini 음성",
      voiceSettings: "음성 설정",
      appSettings: "앱 설정",
      conversationControl: "대화 제어",
      image: "이미지",
      fromFile: "파일에서",
      fromURL: "URL에서",
      speechInput: "음성 입력",
      importFile: "파일 가져오기",
      attachImage: "메시지에 이미지 파일 첨부",
      importFromDoc: "문서 파일에서 텍스트 가져오기",
      importFromWeb: "웹 URL에서 텍스트 가져오기",
      startStopVoice: "음성 입력 시작/중지",
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
        connecting: "연결 중...",
        readyForInput: "입력 준비",
        responding: "응답 중",
        responseReceived: "응답 수신 완료",
        readyToStart: "시작 준비 완료",
        verifyingToken: "토큰 확인 중",
        operationTimedOut: "작업 시간 초과. UI가 재설정되었습니다.",
        languageChanged: "언어가 변경되었습니다:",
        webSpeechNotAvailable: "이 브라우저에서는 음성 인식 API를 사용할 수 없습니다",
        generatingAIUserResponse: "AI 사용자 응답 생성 중...",
        aiUserResponseGenerated: "AI 사용자 응답이 생성되었습니다",
        generatingResponse: "어시스턴트 응답 생성 중...",
        operationCanceled: "작업이 취소되었습니다",
        thinking: "생각 중",
        spinnerStarting: "시작 중",
        spinnerCallingFunctions: "함수 호출 중",
        spinnerReceivingResponse: "응답 수신 중",
        spinnerGeneratingAIUser: "AI 사용자 응답 생성 중",
        spinnerSearchingWeb: "웹 검색 중",
        spinnerProcessing: "처리 중",
        spinnerProcessingRequest: "요청 처리 중",
        spinnerProcessingTools: "도구 처리 중",
        spinnerListening: "듣는 중...",
        spinnerProcessingSpeech: "음성 처리 중...",
        thinkingProcess: "사고 과정",
        reasoningProcess: "추론 과정",
        processingMessage: "샘플 메시지 처리 중",
        sampleTimeout: "샘플 메시지가 시간 초과되었습니다. 다시 시도해주세요.",
        uploadNotAvailable: "업로드 기능을 사용할 수 없습니다",
        uploadSuccess: "업로드 성공",
        uploadError: "파일 업로드 오류",
        convertError: "문서 변환 오류",
        fetchError: "웹페이지 가져오기 오류",
        selectFileImport: "가져올 파일을 선택해주세요",
        sessionImported: "세션을 성공적으로 가져왔습니다",
        importError: "세션 가져오기 오류",
        voiceRecognitionFinished: "음성 인식 완료",
        maskCreated: "마스크 생성됨:",
        maskRemoved: "마스크 제거됨",
        pdfUploadError: "이미지 생성 앱에서는 PDF 파일을 업로드할 수 없습니다",
        connected: "연결됨",
        disconnected: "연결 끊김",
        connectionLost: "연결이 끊겼습니다",
        reconnecting: "다시 연결 중...",
        noAppsAvailable: "사용 가능한 앱이 없습니다 - 설정에서 API 키를 확인하세요"
      },
      session: {
        startSession: "세션 시작",
        continueSession: "세션 계속"
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
      openBrowser: "Navegador",
      sharedFolder: "Compartida",
      quit: "Salir",
      send: "Enviar",
      clear: "Limpiar",
      voice: "Voz",
      settings: "Configuración",
      run: "Ejecutar",
      version: "Versión",
      conversationLanguage: "Idioma de Conversación",
      voiceChatControls: "Controles de Interacción de Chat de Voz",
      voiceChatOperationControl: "Control de Operación de Chat de Voz",
      statistics: "Estadísticas",
      clickToToggle: "Clic para alternar",
      tokensInSystemPrompts: "Tokens en todos los prompts del sistema",
      tokensInUserMessages: "Tokens en todos los mensajes del usuario",
      tokensInAssistantMessages: "Tokens en todos los mensajes del asistente",
      tokensInActiveMessages: "Tokens en todos los mensajes activos",
      tokensInAllMessages: "Tokens en todos los mensajes",
      numberOfAllMessages: "Número de todos los mensajes",
      numberOfActiveMessages: "Número de mensajes activos",
      dialog: "Diálogo",
      user: "Usuario",
      assistant: "Asistente",
      aiAssistant: "Asistente IA",
      aiUser: "Usuario IA",
      generateAIUserResponse: "Generar respuesta de usuario IA basada en la conversación",
      generateAIUserResponsePerplexity: "Generar respuesta de usuario IA (Perplexity requiere mensajes alternos usuario/asistente)",
      role: "Rol",
      roleOptions: {
        user: "Usuario",
        sampleUser: "Usuario (para agregar a mensajes anteriores)",
        sampleAssistant: "Asistente (para agregar a mensajes anteriores)",
        sampleSystem: "Sistema (para proporcionar dirección adicional)"
      },
      messagePlaceholder: "Ingrese un mensaje o haga clic en el botón de entrada de voz para usar voz...",
      pressToSend: "Presione el botón Enviar para enviar el mensaje.",
      resetDescription: "Presione \"Reiniciar\" para limpiar la conversación mientras mantiene la selección actual de la aplicación.",
      imagePdf: "Imagen/PDF",
      maxContextSize: "Tamaño máximo del contexto",
      maxOutputTokens: "Tokens máximos de salida",
      model: "Modelo",
      reasoningEffort: "Esfuerzo de razonamiento",
      pdfToDb: "PDF → BD",
      temperature: "Temperatura",
      presencePenalty: "Penalización de presencia",
      frequencyPenalty: "Penalización de frecuencia",
      showInitialPromptAssistant: "Mostrar prompt inicial del asistente",
      promptCaching: "Caché de prompts",
      webSearch: "Búsqueda web",
      showInitialPromptAIUser: "Mostrar prompt inicial del usuario IA",
      startFromAssistant: "Comenzar desde el asistente",
      mathRendering: "Renderizado matemático",
      autoSpeech: "Voz automática",
      easySubmit: "Envío fácil",
      easySubmitHint: "（Con tecla Enter o botón de parada）",
      autoScroll: "Desplazamiento automático durante la transmisión",
      webSpeechVoice: "Voz de Web Speech API",
      ttsSpeed: "Velocidad TTS",
      baseApp: "Aplicación base",
      systemSettings: "Configuración del sistema",
      speech: "Voz",
      sessionLabel: "Sesión",
      pdfDatabase: "Base de datos PDF",
      monadicChatInfo: "Información de Monadic Chat",
      monadicChatStatus: "Estado de Monadic Chat",
      aiAssistantAndUser: "Asistente IA & Usuario IA",
      github: "GitHub",
      version: "Versión",
      currentBaseApp: "Aplicación Actual",
      selectApp: "Seleccionar App",
      searchApps: "Buscar apps...",
      availableApps: "Apps Disponibles",
      notStarted: "No iniciado",
      notSelected: "No seleccionado",
      notConfigured: "No configurado",
      noDataAvailable: "Sin datos",
      reset: "Reiniciar",
      import: "Importar",
      export: "Exportar",
      homepage: "Página principal",
      cancelQuery: "Cancelar consulta",
      toggleMenu: "Alternar menú",
      status: "Estado",
      mode: "Modo",
      standalone: "Independiente",
      server: "Servidor",
      network: "Red",
      textToSpeechProvider: "Proveedor de texto a voz",
      speechToTextProvider: "Proveedor de voz a texto",
      elevenLabsVoice: "Voz de Elevenlabs",
      openAIVoice: "Voz de OpenAI",
      geminiVoice: "Voz de Gemini",
      voiceSettings: "Configuración de voz",
      appSettings: "Configuración de aplicación",
      conversationControl: "Control de conversación",
      image: "Imagen",
      fromFile: "Desde archivo",
      fromURL: "Desde URL",
      speechInput: "Entrada de voz",
      importFile: "Importar archivo",
      attachImage: "Adjuntar archivo de imagen al mensaje",
      importFromDoc: "Importar texto desde archivo de documento",
      importFromWeb: "Importar texto desde URL web",
      startStopVoice: "Iniciar/detener grabación de voz",
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
        connecting: "Conectando...",
        readyForInput: "Listo para entrada",
        responding: "RESPONDIENDO",
        responseReceived: "Respuesta recibida",
        readyToStart: "Listo para comenzar",
        verifyingToken: "Verificando token",
        operationTimedOut: "Operación agotada. IU reiniciada.",
        languageChanged: "Idioma cambiado a",
        webSpeechNotAvailable: "API de voz no disponible en este navegador",
        generatingAIUserResponse: "Generando respuesta de usuario IA...",
        aiUserResponseGenerated: "Respuesta de usuario IA generada",
        generatingResponse: "Generando respuesta del asistente...",
        operationCanceled: "Operación cancelada",
        thinking: "PENSANDO",
        spinnerStarting: "Iniciando",
        spinnerCallingFunctions: "Llamando funciones",
        spinnerReceivingResponse: "Recibiendo respuesta",
        spinnerGeneratingAIUser: "Generando respuesta de usuario IA",
        spinnerSearchingWeb: "Buscando en la web",
        spinnerProcessing: "Procesando",
        spinnerProcessingRequest: "Procesando solicitud",
        spinnerProcessingTools: "Procesando herramientas",
        spinnerListening: "Escuchando...",
        spinnerProcessingSpeech: "Procesando voz...",
        thinkingProcess: "Proceso de Pensamiento",
        reasoningProcess: "Proceso de Razonamiento",
        processingMessage: "Procesando mensaje de muestra",
        sampleTimeout: "El mensaje de muestra agotó el tiempo. Por favor intente de nuevo.",
        uploadNotAvailable: "Funcionalidad de carga no disponible",
        uploadSuccess: "cargado exitosamente",
        uploadError: "Error al cargar archivo",
        convertError: "Error al convertir documento",
        fetchError: "Error al obtener página web",
        selectFileImport: "Por favor seleccione un archivo para importar",
        sessionImported: "Sesión importada exitosamente",
        importError: "Error al importar sesión",
        voiceRecognitionFinished: "Reconocimiento de voz finalizado",
        maskCreated: "Máscara creada para",
        maskRemoved: "Máscara eliminada",
        pdfUploadError: "Los archivos PDF no se pueden cargar en aplicaciones de generación de imágenes",
        connected: "Conectado",
        disconnected: "Desconectado",
        connectionLost: "Conexión perdida",
        reconnecting: "Reconectando...",
        noAppsAvailable: "No hay aplicaciones disponibles - verifique las claves API en configuración"
      },
      session: {
        startSession: "Iniciar Sesión",
        continueSession: "Continuar Sesión"
      }
    }
  }
};

// Web UI i18n helper class
class WebUIi18n {
  constructor() {
    this.currentLanguage = 'en';
    this.translations = webUITranslations;
    this.initialized = false;
    this.initPromise = null;
  }

  setLanguage(language) {
    console.log(`[WebUIi18n] Setting language to: ${language}`);
    if (this.translations[language]) {
      this.currentLanguage = language;
      this.updateUIText();
      console.log(`[WebUIi18n] Language set successfully to: ${language}`);
      return true;
    }
    console.warn(`[WebUIi18n] Language ${language} not found, using English`);
    this.currentLanguage = 'en';
    this.updateUIText();
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
    console.log(`[WebUIi18n] Updating UI text for language: ${this.currentLanguage}`);
    const elementsCount = document.querySelectorAll('[data-i18n]').length;
    console.log(`[WebUIi18n] Found ${elementsCount} elements with data-i18n attribute`);
    
    // Update role selector options
    const roleOptions = document.querySelectorAll('#select-role option');
    if (roleOptions.length > 0) {
      roleOptions[0].textContent = this.t('ui.roleOptions.user') || 'User';
      roleOptions[1].textContent = this.t('ui.roleOptions.sampleUser') || 'User (to add to past messages)';
      roleOptions[2].textContent = this.t('ui.roleOptions.sampleAssistant') || 'Assistant (to add to past messages)';
      roleOptions[3].textContent = this.t('ui.roleOptions.sampleSystem') || 'System (to provide additional direction)';
    }
    
    // Update elements with data-i18n attribute
    document.querySelectorAll('[data-i18n]').forEach(element => {
      const key = element.getAttribute('data-i18n');
      const translation = this.t(key);
      
      if (element.tagName === 'INPUT' && element.type === 'button') {
        element.value = translation;
      } else if (element.placeholder !== undefined) {
        element.placeholder = translation;
      } else {
        // Special handling for TTS Speed label with value span
        if (key === 'ui.ttsSpeed') {
          const valueSpan = element.querySelector('#tts-speed-value');
          if (valueSpan) {
            const currentValue = valueSpan.textContent;
            element.innerHTML = translation + ' (<span id="tts-speed-value">' + currentValue + '</span>)';
          } else {
            element.textContent = translation;
          }
        } else {
          // Preserve icons and other child elements
          const icon = element.querySelector('i');
          const small = element.querySelector('small');
          const spanWithId = element.querySelector('span[id]');
          
          if (icon && small) {
            // Both icon and small tag present
            const iconHTML = icon.outerHTML;
            const smallHTML = small.outerHTML;
            element.innerHTML = iconHTML + ' ' + translation + ' ' + smallHTML;
          } else if (icon && spanWithId) {
            // Icon and span with ID (like value displays)
            const iconHTML = icon.outerHTML;
            const spanHTML = spanWithId.outerHTML;
            element.innerHTML = iconHTML + ' ' + translation + ' ' + spanHTML;
          } else if (icon) {
            // Only icon present
            const iconHTML = icon.outerHTML;
            element.innerHTML = iconHTML + ' ' + translation;
          } else if (small) {
            // Only small tag present
            const smallHTML = small.outerHTML;
            const textNode = Array.from(element.childNodes).find(node => node.nodeType === Node.TEXT_NODE);
            if (textNode) {
              textNode.textContent = translation + ' ';
            } else {
              element.innerHTML = translation + ' ' + smallHTML;
            }
          } else if (spanWithId) {
            // Span with ID present (preserve it)
            const spanHTML = spanWithId.outerHTML;
            element.innerHTML = translation + ' ' + spanHTML;
          } else {
            // No special elements, just replace text
            element.textContent = translation;
          }
        }
      }
    });
    
    // Update title attributes with data-i18n-title
    document.querySelectorAll('[data-i18n-title]').forEach(element => {
      const key = element.getAttribute('data-i18n-title');
      const translation = this.t(key);
      element.setAttribute('title', translation);
    });
    
    // Update placeholder attributes with data-i18n-placeholder
    document.querySelectorAll('[data-i18n-placeholder]').forEach(element => {
      const key = element.getAttribute('data-i18n-placeholder');
      const translation = this.t(key);
      element.setAttribute('placeholder', translation);
    });
    
    // Update specific UI elements that need special handling
    this.updateSpecificElements();
  }

  updateSpecificElements() {
    // Update Press Send button message with special formatting
    const pressToSendElement = document.querySelector('[data-i18n="ui.pressToSend"]');
    if (pressToSendElement) {
      const translation = this.t('ui.pressToSend');
      const sendText = this.t('ui.send');
      // Keep the special formatting for Send button - handle different languages
      if (this.currentLanguage === 'ja') {
        pressToSendElement.innerHTML = translation.replace('送信', '<span class="text-secondary"> 送信 <i class="fas fa-paper-plane"></i></span>');
      } else if (this.currentLanguage === 'zh') {
        pressToSendElement.innerHTML = translation.replace('发送', '<span class="text-secondary"> 发送 <i class="fas fa-paper-plane"></i></span>');
      } else if (this.currentLanguage === 'ko') {
        pressToSendElement.innerHTML = translation.replace('전송', '<span class="text-secondary"> 전송 <i class="fas fa-paper-plane"></i></span>');
      } else if (this.currentLanguage === 'es') {
        pressToSendElement.innerHTML = translation.replace('Enviar', '<span class="text-secondary"> Enviar <i class="fas fa-paper-plane"></i></span>');
      } else {
        pressToSendElement.innerHTML = translation.replace('Send', '<span class="text-secondary"> Send <i class="fas fa-paper-plane"></i></span>');
      }
    }
    
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
  
  // Initialize i18n with a Promise
  init() {
    if (this.initPromise) {
      return this.initPromise;
    }
    
    this.initPromise = new Promise((resolve) => {
      // Initialize with saved language preference
      const savedUILanguage = getCookie('ui-language') || 'en';
      this.setLanguage(savedUILanguage);
      this.initialized = true;
      
      // Update session button text
      this.updateSessionButton();
      
      console.log('[WebUIi18n] Initialization complete');
      resolve();
    });
    
    return this.initPromise;
  }
  
  // Helper method to update session button
  updateSessionButton() {
    if (typeof messages !== 'undefined' && messages && messages.length > 0) {
      const continueText = this.t('ui.session.continueSession');
      $("#start-label").text(continueText);
    } else {
      const startText = this.t('ui.session.startSession');
      $("#start-label").text(startText);
    }
  }
  
  // Ensure i18n is ready before using
  ready() {
    if (!this.initPromise) {
      return this.init();
    }
    return this.initPromise;
  }
}

// Create global instance
const webUIi18n = new WebUIi18n();

// Create a global promise for i18n readiness
window.i18nReady = webUIi18n.ready();

// Safe translation helper that returns fallback if i18n not ready
window.safeTranslate = function(key, fallback) {
  if (webUIi18n && webUIi18n.initialized) {
    return webUIi18n.t(key);
  }
  return fallback || key;
};

// Function to get cookie value
function getCookie(name) {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) return parts.pop().split(';').shift();
  return null;
}

// Initialize with saved language preference
document.addEventListener('DOMContentLoaded', () => {
  // Clean up old interface-language cookie if exists
  if (getCookie('interface-language')) {
    document.cookie = 'interface-language=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
  }
  
  // Initialize i18n system
  webUIi18n.init().then(() => {
    console.log('[WebUIi18n] Ready for use');
  });
  
  // Conversation language selector only changes conversation language, NOT UI
  const conversationLanguageSelector = document.getElementById('conversation-language');
  if (conversationLanguageSelector) {
    // Set initial value from cookie if exists
    const savedConversationLanguage = getCookie('conversation-language');
    if (savedConversationLanguage) {
      conversationLanguageSelector.value = savedConversationLanguage;
    }
    
    conversationLanguageSelector.addEventListener('change', (event) => {
      const newLanguage = event.target.value;
      console.log(`[WebUIi18n] Conversation language changed to: ${newLanguage}`);
      // Save to cookie for persistence (for AI conversation language only)
      document.cookie = `conversation-language=${newLanguage}; path=/; max-age=31536000`;
      // DO NOT change UI language here
    });
  }
});

// Listen for interface language changes from Electron
if (window.electronAPI && typeof window.electronAPI.onInterfaceLanguageChanged === 'function') {
  window.electronAPI.onInterfaceLanguageChanged((event, data) => {
    if (data.language) {
      webUIi18n.setLanguage(data.language);
      // Also save to cookie for external browser
      document.cookie = `interface-language=${data.language}; path=/; max-age=31536000`;
    }
  });
}