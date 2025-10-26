# Monadic Chat Web インターフェース

![](../assets/images/monadic-chat-web.png ':size=700')

## ブラウザモード :id=browser-modes

Monadic Chatは2つの異なるブラウザモードでWebインターフェースにアクセスすることができます：

### 内部ブラウザモード :id=internal-browser-mode

内部ブラウザモードは、Electronデスクトップアプリケーション内で動作し、Monadic Chat専用の機能を提供します。

内部ブラウザモードで実行すると、右下に5つのボタンが表示されます：
- **ズームイン**：ページを拡大
- **ズームアウト**：ページを縮小
- **ズームリセット**：ページのズームをデフォルトに戻す
- **新規セッション**：セッションデータをクリアして初期アプリに戻す
- **Monadic Chatコンソール**：メインコンソールウィンドウを表示

### 外部ブラウザモード :id=external-browser-mode

外部ブラウザモードでは、Monadic ChatはデフォルトのWebブラウザを起動し、ローカルサーバー (`http://localhost:4567`) に接続します。

## アプリケーションモード :id=application-modes

**スタンドアロンモード（デフォルト）**<br />
個人使用のため単一デバイスでローカルに実行します。

**サーバーモード**<br />
ローカルネットワーク上の複数デバイスから同じMonadic Chatインスタンスに接続できます。インターフェースは異なる画面サイズに適応します。セキュリティ上の理由から、Jupyter Notebook機能はデフォルトで無効化されます。

アプリケーションモードはコンソール設定パネルで設定できます。

## 言語設定 :id=language-settings

インターフェースは58の言語をサポートしています。Infoパネルのドロップダウンから希望の言語を選択すると、音声認識、音声合成、AI応答言語が設定されます。アラビア語、ヘブライ語、ペルシャ語、ウルドゥー語では右から左（RTL）のテキスト表示が自動的に適用されます。

会話中でもいつでも言語を変更できます。言語設定はCookieに保存され、次回の起動時に復元されます。

## システム設定画面 :id=system-settings-screen

![](../assets/images/chat-settings.png ':size=700')

**Base App** <br />
基本アプリの中から1つを選択します。各アプリでは異なるデフォルトパラメータと初期プロンプトが設定されています。詳細は[Base Apps](./basic-apps.md)を参照してください。

**Model** <br />
使用するAIモデルを選択します。使用可能なモデルは選択中のアプリによって異なります。

**推論/思考コントロール** <br />
高度な思考をサポートするモデルの推論深度を調整します。セレクターは各プロバイダーの用語に適応します（OpenAI: Reasoning Effort、Anthropic: Thinking Level、Google: Thinking Mode、xAI: Reasoning Effort、DeepSeek: Reasoning Mode、Perplexity: Research Depth）。

**Max Output Tokens** <br />
APIレスポンスの最大トークン数を制限します。

**Max Context Size** <br />
会話コンテキストに保持する最大メッセージ数です。

**Parameters**<br />
Temperature、Top P、Presence Penalty、Frequency Penalty

**Show Initial Prompt**<br />
AIに送信するシステムプロンプトを表示または編集します。

**Show Initial Prompt for AI-User**<br />
AIユーザー機能のシステムプロンプトを表示または編集します。

**Prompt Caching**<br />
プロンプトキャッシングを有効にしてAPIコストを削減し、レスポンス時間を向上させます。

**Math Rendering**<br />
MathJaxを使用して数式をレンダリングします。

**AI User Provider**<br />
AIユーザー機能のプロバイダーを選択します。この機能は人間のユーザーが書いたかのような後続メッセージを自動生成します。

**Start from assistant**<br />
会話を始める時にアシスタント側が最初のメッセージを発します。

**Chat Interaction Controls**<br />
音声ベースの会話のためのオプションです。`toggle all`リンクをクリックすると、すべてのオプションを一度に有効/無効にできます。

**Auto speech**<br />
アシスタントの応答を合成音声で自動的に読み上げます。

**Easy submit**<br />
Sendボタンをクリックせずに、Enterキーでメッセージを送信します。

**Web検索**<br />
AIが最新情報を検索できるようにします。ツール/関数呼び出しをサポートするモデルで利用可能です。

**Start Session / Continue Session** <br />
新しいチャットを開始するか、現在の会話を続けます。

## 基本情報パネル :id=info-panel

![](../assets/images/monadic-chat-info.png ':size=400')

**Monadic Chat Info**<br />
関連ウェブサイトへのリンクと現在のバージョンです。

**Current Base App**<br />
選択中のアプリの名前と説明です。

## ステータスパネル :id=status-panel

![](../assets/images/monadic-chat-status.png ':size=400')

**Monadic Chat Status**<br />
現在の会話の状態をリアルタイムで更新します。

**Model Selected**<br />
現在選択されているモデルです。

**Model Chat Stats**<br />
現在のセッションのメッセージ数とトークン数です。

## セッション表示パネル :id=session-panel

![](../assets/images/monadic-chat-session.png ':size=400')

**Reset**<br />
`Reset`ボタンまたは左上のロゴをクリックすると、現在のアプリ選択を保持したまま会話をクリアします。

**Settings**<br />
システム設定パネルに戻ります。会話に戻るには`Continue Session`をクリックします。

**Import**<br />
外部JSONファイルから会話データを読み込みます。

**Export**<br />
現在の会話を外部JSONファイルに保存します。

**PDF出力**<br />
現在の会話をシンタックスハイライトと書式設定付きのPDFファイルとして保存します。

## 音声設定パネル :id=speech-settings-panel

![](../assets/images/monadic-chat-tts.png ':size=400')

!> 音声機能を使用するには、Google Chrome、Microsoft Edge、またはSafariブラウザを使用する必要があります。

**Speech-to-Text Model**<br />
音声認識に使用するモデルを選択します。OpenAIおよびGeminiのモデルが利用可能です。

**Text-to-Speech Provider**<br />
音声合成のプロバイダーを選択します（OpenAI、ElevenLabs、Gemini、Web Speech API）。

**Text-to-Speech Voice**<br />
音声合成に使用する声を選択します。利用可能な声は選択したプロバイダーに依存します。

**TTS Speed**<br />
音声合成の再生速度を調整します（0.7～1.2）。

## PDFデータベース表示パネル :id=pdf-database-display-panel

![](../assets/images/monadic-chat-pdf-db.png ':size=400')

?> このパネルはPDF読み込み機能を備えたアプリを選択しているときだけ表示されます。

**Uploaded PDF**<br />
ここには、`Import PDF`ボタンをクリックしてアップロードしたPDFのリストが表示されます。PDFをアップロードする際に、ファイルに個別の表示名を付けることができます。指定しない場合はオリジナルのファイル名が使用されます。複数のPDFファイルをアップロードすることが可能です。PDFファイル表示名の右側のゴミ箱アイコンをクリックするとそのPDFファイルの内容が破棄されます。

!> **ローカルストレージ（PGVector）を使用している場合**: Monadic Chatをアップデートしたり、コンテナを再構築したりする際にはデータベースが破棄される可能性がありますので、後でリストアするために`Export Document DB`機能でデータをエクスポートしてください。詳細は[PDFストレージモード](./pdf_storage.md)を参照してください。
