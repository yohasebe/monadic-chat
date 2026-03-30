import globals from "globals";

/**
 * ESLint Flat Config for Monadic Chat
 *
 * Target: Browser-side vanilla JavaScript (no ES modules, no bundler)
 * Pattern: IIFE modules with window.* exports, jQuery, global functions
 *
 * Strategy: Start with bug-detection rules only.
 * Style/formatting rules are intentionally omitted to avoid noise.
 */
export default [
  // ── Global ignores ──────────────────────────────────────────
  {
    ignores: [
      "node_modules/**",
      "dist/**",
      "build/**",
      "docker/services/ruby/public/vendor/**",
      "docker/services/ruby/public/js/monadic/model_spec.js", // Large data-only SSOT
      "**/*.min.js",
      "**/*.bundle.js",
      "test/**",
      "config/**",
      "scripts/**",
      "app/**", // Electron main process (different environment)
    ],
  },

  // ── Browser JavaScript (main target) ────────────────────────
  {
    files: ["docker/services/ruby/public/js/monadic/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script", // Not ES modules — uses IIFE + window.*
      globals: {
        ...globals.browser,

        // ── CommonJS (dual-export pattern for Jest) ──
        module: "readonly",

        // ── DOM helpers (dom-helpers.js) ──
        $id: "readonly",
        $show: "readonly",
        $hide: "readonly",
        $toggle: "readonly",
        $on: "readonly",
        $dispatch: "readonly",

        // ── Third-party libraries ──
        hljs: "readonly",
        mermaid: "readonly",
        ABCJS: "readonly",
        GraphViewer: "readonly",
        MathJax: "readonly",
        katex: "readonly",
        OpusMediaRecorder: "readonly",
        bootstrap: "readonly",
        i18next: "readonly",

        // ── i18n ──
        webUIi18n: "readonly",

        // ── Global state variables (utilities.js, websocket.js) ──
        apps: "writable",
        params: "writable",
        originalParams: "writable",
        messages: "writable",
        lastApp: "writable",
        mids: "writable",
        images: "writable",
        ws: "writable",
        verified: "writable",
        autoScroll: "writable",
        chatBottom: "writable",
        mainPanel: "writable",
        currentPdfData: "writable",
        initialLoadComplete: "writable",
        loadedApp: "writable",
        defaultApp: "readonly",
        stop_apps_trigger: "writable",

        // ── Browser detection (utilities.js) ──
        runningOnChrome: "readonly",
        runningOnEdge: "readonly",
        runningOnFirefox: "readonly",
        runningOnSafari: "readonly",

        // ── Utility functions (utilities.js, ui-utilities.js) ──
        setCookie: "readonly",
        getCookie: "readonly",
        setAlert: "readonly",
        setStats: "readonly",
        setInputFocus: "readonly",
        listModels: "readonly",
        removeMarkdown: "readonly",
        removeEmojis: "readonly",
        removeCode: "readonly",
        getTranslation: "readonly",
        isSystemBusy: "readonly",
        isElementInViewport: "readonly",
        formatInfo: "readonly",
        loadParams: "readonly",
        resetParams: "readonly",
        doResetActions: "readonly",
        updateItemStates: "readonly",
        updateAppBadges: "readonly",
        updateAppSelectIcon: "readonly",
        updateWebSearchBasic: "readonly",
        hasCurrentAppFromServer: "readonly",
        getProviderFromGroup: "readonly",
        getDefaultModelForApp: "readonly",
        getModelsForApp: "readonly",
        isPdfSupportedForModel: "readonly",
        isImageGenerationApp: "readonly",
        isMaskEditingEnabled: "readonly",
        isFileInputsSupportedForModel: "readonly",
        isResponsesApiModel: "readonly",
        adjustScrollButtons: "readonly",
        cleanupAllTooltips: "readonly",
        setupTextarea: "readonly",
        simulateEscapeKey: "readonly",
        setupSearchCloseHandlers: "readonly",
        deleteMessage: "readonly",
        setBaseAppDescription: "readonly",
        updateAIUserButtonState: "readonly",

        // ── Card & message rendering (card-renderer.js, cards.js, ws-content-renderer.js) ──
        escapeHtml: "readonly",
        createCard: "readonly",
        attachEventListeners: "readonly",
        detachEventListeners: "readonly",
        cancelEditMode: "readonly",
        cleanupCardTextListeners: "readonly",
        updateCardTurnNumbers: "readonly",
        getCardTurnNumber: "readonly",
        deleteMessageAndSubsequent: "readonly",
        deleteMessageOnly: "readonly",
        deleteSystemMessage: "readonly",
        renderMessage: "readonly",

        // ── Content renderers (ws-content-renderer.js) ──
        applyMathJax: "readonly",
        applyMermaid: "readonly",
        applyDrawIO: "readonly",
        applyAbc: "readonly",
        applyToggle: "readonly",
        addToggleSourceCode: "readonly",
        formatSourceCode: "readonly",
        cleanupListCodeBlocks: "readonly",
        setCopyCodeButton: "readonly",

        // ── Audio state variables (websocket.js closure → window sync) ──
        mediaSource: "writable",
        sourceBuffer: "writable",
        audioDataQueue: "writable",
        processAudioDataQueue: "writable",
        iosAudioBuffer: "writable",
        iosAudioQueue: "writable",
        iosAudioElement: "writable",
        isIOSAudioPlaying: "writable",

        // ── Audio & TTS (tts.js, ws-audio-*.js) ──
        audioInit: "readonly",
        ttsSpeak: "readonly",
        ttsStop: "readonly",
        initWebSpeech: "readonly",
        populateWebSpeechVoices: "readonly",
        showTtsNotice: "readonly",
        addToAudioQueue: "readonly",
        clearAudioQueue: "readonly",
        stopAllActiveAudio: "readonly",
        resetAudioElements: "readonly",
        detectSilence: "readonly",
        soundToBase64: "readonly",

        // ── Auto Speech (ws-auto-speech.js) ──
        isAutoSpeechSuppressed: "readonly",
        setAutoSpeechSuppressed: "readonly",
        scheduleAutoTtsSpinnerTimeout: "readonly",
        resetAutoSpeechSpinner: "readonly",
        checkAndHideSpinner: "readonly",
        removeStopButtonHighlight: "readonly",
        ensureThinkingSpinnerVisible: "readonly",
        registerAudioElement: "readonly",

        // ── WebSocket handler modules (ws-*.js) ──
        WsHtmlHandler: "readonly",
        WsConnectionHandler: "readonly",
        WsAIUserHandler: "readonly",
        WsAppDataHandlers: "readonly",
        WsErrorHandler: "readonly",
        WsInfoHandler: "readonly",
        WsMessageRenderer: "readonly",
        WsSessionHandler: "readonly",
        WsStreamingHandler: "readonly",
        WsThinkingHandler: "readonly",
        WsTTSHandler: "readonly",
        WsToolHandler: "readonly",
        WsContentRenderer: "readonly",
        WsAudioQueue: "readonly",
        WsAudioPlayback: "readonly",
        WsAudioConstants: "readonly",
        WsAutoSpeech: "readonly",
        wsHandlers: "writable",

        // ── Module objects ──
        modelSpec: "readonly",
        ReasoningMapper: "readonly",
        ReasoningLabels: "readonly",
        reasoningUIManager: "readonly",
        ContextPanel: "readonly",
        MarkdownRenderer: "readonly",
        WorkflowViewer: "readonly",
        UIConfig: "readonly",
        SessionState: "readonly",
        StorageHelper: "readonly",
        uiUtils: "readonly",
        formHandlers: "readonly",

        // ── Model utilities (model_utils.js) ──
        getModelSpecWithFallback: "readonly",
        modelRequiresConfirmation: "readonly",
        isModelDeprecated: "readonly",
        getModelSuccessor: "readonly",
        isModelUiHidden: "readonly",

        // ── Fragment handling (ws-fragment-handler.js) ──
        handleFragmentMessage: "readonly",
        debugFragmentSummary: "readonly",
        resetFragmentDebug: "readonly",

        // ── Thinking / Reasoning UI ──
        renderThinkingBlock: "readonly",
        toggleThinkingBlock: "readonly",
        setReasoningStreamActive: "readonly",
        isReasoningStreamActive: "readonly",

        // ── Tool status (ws-tool-handler.js) ──
        clearToolStatus: "readonly",
        updateToolStatus: "readonly",

        // ── Image handling (select_image.js) ──
        openMaskEditor: "readonly",
        fileToBase64: "readonly",
        imageToBase64: "readonly",
        updateFileDisplay: "readonly",
        limitImageCount: "readonly",
        clearAllImages: "readonly",
        getDocumentIcon: "readonly",
        isDocumentType: "readonly",
        getMimeTypeFromExtension: "readonly",

        // ── WebSocket connection (websocket.js) ──
        connect_websocket: "readonly",
        reconnect_websocket: "readonly",
        closeCurrentWebSocket: "readonly",
        startPing: "readonly",
        stopPing: "readonly",
        getMonadicTabId: "readonly",
        handleVisibilityChange: "readonly",

        // ── Shims & module loading ──
        loadModuleWithShim: "readonly",
        installShims: "readonly",
        shims: "readonly",
        websearchTavilyCheck: "readonly",

        // ── Alert & status (alert-manager.js) ──
        setAlertClass: "readonly",
        clearStatusMessage: "readonly",
        clearErrorCards: "readonly",

        // ── Other project globals ──
        toggleItem: "readonly",
        applyCollapseStates: "readonly",
        setCookieValues: "readonly",
        highlightStopButton: "readonly",
        handleMCPStatus: "readonly",
        initializeMediaSourceForAudio: "readonly",
        DEFAULT_APP: "readonly",
      },
    },
    rules: {
      // ── Bug detection (high value, low noise) ──
      "no-undef": "warn",               // Catch typos and missing globals
      "no-unused-vars": ["warn", {
        args: "none",                    // Allow unused function params (_data etc.)
        varsIgnorePattern: "^_",         // Allow _prefixed unused vars
        caughtErrors: "none",           // Allow unused catch params
      }],
      "no-redeclare": ["error", { builtinGlobals: false }],  // Prevent variable re-declaration (allow redefining config globals)
      "no-dupe-keys": "error",           // Prevent duplicate object keys
      "no-duplicate-case": "error",      // Prevent duplicate switch cases
      "no-unreachable": "warn",          // Dead code after return/throw
      "no-constant-condition": "warn",   // Likely logic errors
      "use-isnan": "error",              // Must use isNaN() for NaN checks
      "valid-typeof": "error",           // Prevent typeof typos
      "eqeqeq": ["warn", "smart"],      // Prefer === but allow == null

      // ── Code quality (medium value) ──
      "no-eval": "error",               // Security: no eval()
      "no-implied-eval": "error",       // Security: no string setTimeout/setInterval
      "no-new-func": "error",           // Security: no new Function()
      "no-debugger": "warn",            // Remove debugger statements
      "no-empty": ["warn", { allowEmptyCatch: true }],  // Allow empty catch blocks
    },
  },
];
