# Monadic Chat Web インターフェース

![](../assets/images/monadic-chat-web.png ':size=700')

## ブラウザモード :id=browser-modes

Monadic Chatは2つの異なるブラウザモードでWebインターフェースにアクセスすることができます：

### 内部ブラウザモード :id=internal-browser-mode

内部ブラウザモードは、Electronデスクトップアプリケーション内でwebview機能を使用して直接実行されます。このモードでは、アプリケーション間の切り替えなしでチャットインターフェースを操作できる統合された体験を提供します。

内部ブラウザモードの利点：
- すべての機能が単一のアプリケーションウィンドウ内に含まれる
- チャットと他のアプリケーション間の完全なコピー/ペーストサポート
- 一般的な操作のためのキーボードショートカット
- 会話検索機能の内蔵
- プラットフォーム間で一貫した体験

内部ブラウザモードで実行すると、インターフェースの右下隅に4つの追加ボタンが表示されます：
- **Zoom In**：ページのズーム倍率を上げる
- **Zoom Out**：ページのズーム倍率を下げる
- **Reset App**：セッションデータをクリアしUIをリロードし、初期アプリ選択状態に戻す
- **Monadic Chat Console**：メインのコンソールウィンドウを表示する

### 外部ブラウザモード :id=external-browser-mode

外部ブラウザモードでは、Monadic ChatはデフォルトのWebブラウザを起動し、ローカルサーバー (`http://localhost:4567`) に接続します。

## アプリケーションモード :id=application-modes

Monadic Chatはサーバーの動作を決定する2つのアプリケーションモードをサポートしています：

### スタンドアロンモード（デフォルト） :id=standalone-mode

スタンドアロンモードでは、Monadic Chatは単一のデバイスでローカルに実行され、localhost（127.0.0.1）にのみバインドされます。これは個人使用のためのデフォルトモードです。

### サーバーモード :id=server-mode

サーバーモードでは、複数のクライアントが単一のMonadic Chatインスタンスに接続できます。サーバーモードで実行する場合：
- Webインターフェースはlocalhostだけでなくすべてのネットワークインターフェース（0.0.0.0）にバインドされます
- ローカルネットワーク上の異なるデバイスから同じMonadic Chatインスタンスにアクセスできます
- インターフェースはレスポンシブで、異なる画面サイズ（タブレットやスマートフォンを含む）に適応します
- セキュリティ上の理由から、Jupyterノートブック機能などの一部の機能は明示的に有効化しない限り無効化されます
- 画面幅が767px以下の場合、モバイル最適化レイアウトが自動的に有効になります

アプリケーションモードは起動時のコンソール設定パネルまたは`~/monadic/config/env`の設定変数を通じて設定できます。

## 言語設定 :id=language-settings

Monadic Chatは、Infoパネルにある統合言語セレクターを通じて包括的な言語サポートを提供します：

### サポートされる言語 :id=supported-languages

インターフェースは58の言語をサポートし、ネイティブ名と英語訳で表示されます（例："日本語 (Japanese)"、"العربية (Arabic)"）。ドロップダウンメニューから希望の言語を選択すると、以下が設定されます：

- 音声入力のための音声認識（STT）言語を設定
- 音声出力のための音声合成（TTS）言語を設定
- AIアシスタントが選択した言語で応答するよう指示（全プロバイダー対応：OpenAI、Claude、Gemini、DeepSeek、Grok、Mistral、Perplexity、Cohere）
- アラビア語、ヘブライ語、ペルシャ語、ウルドゥー語の場合、右から左（RTL）のテキスト表示を自動適用

### 動的な言語切り替え :id=dynamic-language-switching

アクティブな会話中でもいつでも言語を変更できます：
- 新しい言語設定は新しいメッセージに即座に反映されます
- 会話中の以前のメッセージは変更されません
- 言語設定はCookieに保存され、次回の訪問時に復元されます

### RTL言語サポート :id=rtl-support

右から左に記述する言語の場合、Monadic Chatは自動的に：
- メッセージコンテンツをRTLテキスト配置で表示
- RTL入力用にメッセージ入力フィールドを調整
- ナビゲーションの一貫性を保つためUIエレメントはLTRレイアウトを維持
- コードブロックと技術的なコンテンツは可読性のためLTR形式を維持

## システム設定画面 :id=system-settings-screen

![](../assets/images/chat-settings.png ':size=700')

**Base App** <br />
Monadic Chatであらかじめ用意された基本アプリの中から1つを選択します。各アプリでは異なるデフォルト・パラメター値が設定されており、固有の初期プロンプトが与えられています。各アプリの特徴については [Base Apps](./basic-apps.md)を参照してください。

**Model** <br />
選択中のアプリで使用可能なモデルが表示されます。各アプリでデフォルトのモデルがある場合、あらかじめ選択状態で表示されますが、目的に応じて変更することができます。

!> 多くの基本アプリではモデルのリストをAPI経由で取得しており、複数のモデルが選択可能です。デフォルトのモデル以外を使用する場合はエラーとなる場合もあります。

**推論/思考コントロール** <br />
高度な推論機能を持つモデルでは、プロバイダ固有のコントロールを表示するようにこのセレクターが自動的に適応します。選択されたプロバイダとモデルに基づいてラベルとオプションが変化します（例：OpenAIの「Reasoning Effort」、Claudeの「Thinking Level」、Geminiの「Thinking Mode」）。オプションは通常、最小から高い計算効率まで範囲があり、応答品質と処理時間のバランスを調整できます。このコントロールは推論/思考機能をサポートするモデルでのみ表示され、標準モデルでは自動的に非表示になります。詳細については[推論・思考機能](./language-models.md#推論思考機能)セクションを参照してください。

**Max Output Tokens** <br />
APIレスポンスで返される最大トークン数を指定します。チェックマークをオンにすると、レスポンスが指定されたトークン数に制限されます。トークンのカウント方法についてはモデルによって異なります。OpenAIのモデルに関しては、[What are tokens and how to count them](https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them)を参照してください。

**Max Context Size** <br />
現在進行中のチャットに含まれるやりとりの中で、アクティブなものとして保つ発話の最大数です。アクティブな発話のみがAPIに文脈情報として送信されます。インアクティブな発話も画面上では参照可能であり、エクスポートの際には保存対象となります。

**Parameters**<br />

下記の要素はパラメターとしてAPIに送られます。各パラメターの詳細はChat APIの[Reference](https://platform.openai.com/docs/api-reference/chat)を参照してください。なお、選択中のモデルで使用できないパラメターは無視されます。

- Temperature（注：推論モデルでは「Reasoning Effort」パラメータに置き換わります）
- Top P
- Presence Penalty
- Frequency Penalty

**Show Initial Prompt**<br />
初期プロンプトとしてAPIに送られるテキスト（システムプロンプトと呼ばれることもあります）を表示または編集するにはオンにします。初期プロンプトによって、会話のキャラクター設定や、レスポンスの形式などを指定することができます。各アプリ の目的に応じたデフォルトのテキストが設定されていますが、自由に変更することが可能です。

**Show Initial Prompt for AI-User**<br />
AIユーザー機能を有効にしたときAIユーザーに与えられる初期プロンプトを表示します。AIユーザーが有効なとき、最初のメッセージは（AIでない）ユーザー自身が作成する必要があります。それ以降はAIアシスタントからのメッセージの内容に応じて、AIが「ユーザーになりきって」メッセージを代わりに作成してくれます。テキストボックスに入力されたAIユーザーによるメッセージをユーザー自身が編集したり、追記したりすることができます。

**Prompt Caching**<br />
APIのプロンプトキャッシング機能を有効にするかどうかを指定します。キャッシングの動作はプロバイダーによって異なります：
- **Anthropic Claude**: 有効にすると、cache_controlを使用してシステムプロンプト、画像、PDFを明示的にキャッシュ対象としてマークします。これによりAPIコストが削減され、レスポンス時間が向上します。
- **OpenAI**: 128トークン以上のプロンプトを5〜10分間自動的にキャッシュします（特別な設定は不要）。これによりキャッシュされた部分のAPIコストが削減されます。この設定はOpenAIの自動キャッシングには影響しませんが、プロバイダー間で切り替える際の一貫性を保つために有効にしておくことをお勧めします。

**Math Rendering**<br />
AIエージェントに数式を表示するときにはMathJax形式を使用するよう依頼し、レスポンス中の数式をMathJaxでレンダリングします。

**AI User Provider**<br />
AIユーザー機能で使用するプロバイダーをドロップダウンメニューから選択します。ドロップダウンには、設定で有効なAPIトークンを設定したプロバイダーのみが表示されます。AIユーザー機能は、あたかも人間のユーザーが書いたかのような応答を自動生成し、会話のテストや異なる入力に対するアシスタントの反応を確認するのに役立ちます。アシスタントが返信した後、AIユーザープロバイダーのドロップダウンの横にある`Run`ボタンをクリックすると、会話の履歴に基づいて自然な後続メッセージが生成され、送信前に編集することができます。この機能は複数のプロバイダー（OpenAI、Claude、Gemini、Cohere、Mistral、Perplexity、DeepSeek、Grok）をサポートし、プロバイダー固有のフォーマット要件を適切に処理します。

セレクター横のバッジは、推論/思考に対応するモデルの場合は `Provider (model - effort)` の形式で表示され、それ以外のモデルでは `Provider (model)` と表示されます。初回ロード時も、モデル一覧の構築完了後に自動的に初期化されるため、再読み込みは不要です。送信時にはプロバイダーごとの既定（推論パラメータ）を自動適用し、未対応のパラメータ（例：推論モデルでのtemperatureなど）は送信しません。

- OpenAI: reasoning/Responsesモデルに `reasoning_effort` を付与し、temperatureは送らない
- Claude: `thinking` を有効化し、effortに応じた `budget_tokens` を安全な範囲で設定
- Gemini: モデルの上限・プリセットに合わせて `thinkingBudget` を設定
- xAI Grok: UIのeffortをプロバイダーの受理値に丸めて送信（例：minimal→low）
- Cohere: reasoning系を有効化し、必要に応じて会話圧縮のワークアラウンドを適用
- Perplexity, DeepSeek: 安全な既定を適用し、未対応のsampling設定は送信しない

**Start from assistant**<br />
オンにすると、会話を始める時にアシスタント側が最初の発話を行います。

**Chat Interaction Controls**<br />
Monadic Chatを音声入力による会話に適した形に設定するためのオプションです。音声入力による会話を行う場合には、以下のオプション（`Start from assistant`, `Auto speech`, `Easy submit`）をすべてオンにするとよいでしょう。`toggle all` リンクをクリックすることで、すべてのオプションを切り替えることができます。チェックされていない項目がある場合はすべてチェックし、すべてチェックされている場合はすべて解除します。

**Auto speech**<br />

オンにすると、アシスタントからのレスポンスが返ってくるタイミングで自動的に合成音声での読み上げが行われます。合成音声のボイス、発話スピード、および使用言語（自動または個別指定）webインターフェイス上で選択可能です。

**Easy submit**<br />

オンにすると、`Send`ボタンをクリックしなくても、キーボードのEnterキーを押すと自動的にテキストエリア内のメッセージが送信されます。もし音声入力中であれば、Enterキーを押すか、`Stop`ボタンをクリックすることで、自動的にメッセージが送信されます。

**Web検索**<br />
有効にすると、AIが最新情報を取得するためにWeb検索を実行できるようになります。このオプションは、ツール/関数呼び出しをサポートするモデルでのみ利用可能です。検索動作はプロバイダーによって異なります：
- OpenAI (gpt-4.1/gpt-4.1-mini): Responses API経由でネイティブWeb検索を使用
- その他のプロバイダー: Tavily APIが設定されている場合に使用
- AIはクエリの文脈に基づいて検索タイミングを判断します


**Start Session / Continue Session** <br />
このボタンをクリックすると、System Settingsで指定したオプションやパラメターのもとにチャットが開始されます。すでにセッションを開始していて、`Settings`ボタンをクリックしてSystem Settingsパネルに戻った場合、このボタンは`Continue Session`と表示されます。クリックすると、会話をリセットせずに進行中の会話に戻ります。

## 基本情報パネル :id=info-panel

![](../assets/images/monadic-chat-info.png ':size=400')

**Monadic Chat Info**<br />
関連するウェブサイトへのリンクとMonadic Chatのバージョンが示されます。`API Usage`をクリックするとOpenAIのページにアクセスします。API Usageで示されるのはAPI使用量の全体であり、Monadic Chatによるものだけとは限らないことに注意してください。バージョン番号の後の括弧には、Monadic Chatのインストール方法（DockerまたはLocal）が表示されます。

**Current Base App**<br />
現在選択している基本アプリの名前と説明が表示されます。Monadic Chatの起動時にはデフォルトのアプリである`Chat`に関する情報が表示されます。

## ステータスパネル :id=status-panel

![](../assets/images/monadic-chat-status.png ':size=400')

**Monadic Chat Status**<br />

Monadic Chatの現在の状況を示します。

**Model Selected**<br />

現在選択されているモデルを表示します。

**Model Chat Stats**<br />

現在のセッションにおいて交わされたメッセージの数やトークンの数などの詳細が示されます。

## セッション表示パネル :id=session-panel

![](../assets/images/monadic-chat-session.png ':size=400')

**Reset**<br />
`Reset`ボタンをクリックすると、現在の会話が破棄され、初期状態に戻りますが、現在のアプリ選択は保持されます。アプリのパラメータはすべてデフォルト値にリセットされます。ドロップダウンから異なるアプリを選択してアプリを変更すると、現在の会話をリセットするかどうかを確認するダイアログが表示されます。アプリを変更するとすべてのパラメータがリセットされるためです。

?> このセッションパネルのResetボタンは現在のアプリ選択を維持しますが、内部ブラウザの右下にあるReset Appボタンは初期アプリ選択状態にもリセットします。

**Settings**<br />
`Settings`ボタンをクリックすると、現在の会話を破棄しないで、System Settingsパネルに戻ります。その後、現在の会話に戻るには`Continue Session`をクリックします。

**Import**<br />
`Import`ボタンをクリックすると、現在の会話を破棄し、外部ファイル（JSON）に保存した会話データを読み込みます。また、外部ファイルに保存された設定が適用されます。

**Export**<br />
`Export`ボタンをクリックすると、現在の設定項目の値と会話データを外部ファイル（JSON）に保存します。

## 音声設定パネル :id=speech-settings-panel

![](../assets/images/monadic-chat-tts.png ':size=400')

!> 音声機能を使用するには、Google Chrome、Microsoft Edge、またはSafariブラウザを使用する必要があります。

**Text-to-Speech Provider**<br />
音声合成に使用するプロバイダーを選択します。以下から選択できます：
- OpenAI（4o TTS、TTS、またはTTS HD）- OpenAI APIキーが必要です
- ElevenLabs - ElevenLabs APIキーが必要です
- Gemini Flash TTS - Gemini APIキーが必要です（gemini-2.5-flash-preview-ttsモデルを使用）
- Gemini Pro TTS - Gemini APIキーが必要です（gemini-2.5-pro-preview-ttsモデルを使用）
- Web Speech API - ブラウザ内蔵の音声合成を使用します（APIキー不要）

**Text-to-Speech Voice**<br />
音声合成に使用する声を指定できます。利用可能な声は選択したプロバイダーによって異なります：
- OpenAI：事前定義された声のセット（Alloy、Echo、Fableなど）から選択
- ElevenLabs：利用可能なElevenLabsの声から選択
- Gemini：8つの利用可能な声から選択（Aoede、Charon、Fenrir、Kore、Orus、Puck、Schedar、Zephyr）
- Web Speech API：システムで利用可能な声から選択（ブラウザ/オペレーティングシステムによって異なります）

**Text-to-Speech Speed**<br />
音声合成の再生速度を0.7（遅い）から1.2（速い）の範囲で調整できます。一般に、ElevenLabsの声はOpenAIの声と比較して、速度を変更した場合の品質が優れています。Web Speech APIも速度調整をサポートしていますが、品質はブラウザやオペレーティングシステムによって異なる場合があります。

**Speech-to-Text (STT) Language**<br />
音声認識にはSpeech-to-Text APIを用いており、`Automatic` が選択されていると異なる言語による音声入力を自動で認識します。特定の言語を指定したい場合にはセレクターで言語を選択してください。Monadic Chatはコンソール設定で設定されたSTTモデルを使用します（デフォルトはgpt-4o-transcribe）。
参考：[Whisper API FAQ](https://help.openai.com/en/articles/7031512-whisper-api-faq)

## PDFデータベース表示パネル :id=pdf-database-display-panel

![](../assets/images/monadic-chat-pdf-db.png ':size=400')

?> このパネルはPDF読み込み機能を備えたアプリを選択しているときだけ表示されます。

**Uploaded PDF**<br />
ここには、`Import PDF`ボタンをクリックしてアップロードしたPDFのリストが表示されます。PDFをアップロードする際に、ファイルに個別の表示名を付けることができます。指定しない場合はオリジナルのファイル名が使用されます。複数のPDFファイルをアップロードすることが可能です。PDFファイル表示名の右側のゴミ箱アイコンをクリックするとそのPDFファイルの内容が破棄されます。

!> PDFファイルから得た情報はテキストエンベディングに変換されて、PGVectorデータベースに格納されます。Monadic Chatをアップデートしたり、コンテナを再構築したりする際にはPDFテキストエンベディングのデータベースが破棄されますので、後でリストアするために`Export Document DB`機能でデータをエクスポートしてください。
