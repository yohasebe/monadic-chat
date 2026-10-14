# メッセージ入力

Monadic Chat コンソールでサーバーを起動し、Web インターフェイスでアプリの選択と各種の設定を行った後に `Start Session` ボタンをクリックするとチャット画面が表示されます。

<!-- SCREENSHOT: メッセージ入力画面 - 上部にチャット履歴エリア、下部にテキストエリア、Send/Speech Input/Image/Text from file/Text from URLなどのボタンが配置されている様子 -->

チャット画面には、テキスト入力エリアとメッセージ送信のための各種ボタンが表示されます。

テキストエリアにメッセージを入力し、`Send` ボタンをクリックすると、メッセージが送信されます。音声入力については下記の[音声入力](#speech-input)を参照してください。

?> 音声入力と音声合成を使って AI エージェントとのチャットをスムーズに行うには、サイドバーの Interaction パネルで `Auto speech` と `Easy submit` をオンにすると便利です。[Voice Chat](../apps/chat-apps.md#voice-chat)アプリではこれらが既定でオンです。

?> `Role` セレクタはメッセージの役割を選びます。通常は `User` を選びます。`User (to add to past messages)` と `Assistant (to add to past messages)` は、送らずに会話にメッセージを加えます。`System (to provide additional direction)` は指示を加えます。詳しくは [FAQ](../faq/faq-user-interface.md) を参照してください。

## 画像のアップロード :id=uploading-images

画像アップロードは、ビジョン機能を持つモデル（OpenAI、Anthropic Claude、xAI Grok、Google Gemini、Mistral、Cohere、DeepSeek、Ollama のビジョンモデル）で利用できます。

`Image`（PDFもサポートするモデルでは`Image/PDF`）をクリックして画像を選択します。対応形式：JPG、JPEG、PNG、GIF、WebP。1 つのメッセージに 5 枚まで添付できます。

<!-- SCREENSHOT: 画像添付ダイアログ - ファイル選択ダイアログが開き、JPG、JPEG、PNG、GIF、WebP形式の画像ファイルを選択できる様子 -->

画像をアップロードすると、メッセージ入力エリアの下に、削除ボタン（×）付きのサムネイルが表示されます。画像はテキストのプロンプトと一緒に送られ、メッセージを送ると添付は外れます。

添付画像は送信前にブラウザ側で縮小されます（長辺最大 2000px、短辺最大 768px）。細部を原寸で解析したい場合は、画像ファイルを共有フォルダに置いて AI に解析を依頼してください — 画像解析スキルを持つアプリは元ファイルを直接読み込み、original 精度での解析を指示できます。

<!-- SCREENSHOT: 画像付きメッセージ - チャット履歴にユーザーがアップロードした画像とAIの画像分析結果が表示されている様子 -->

## PDF のアップロード :id=uploading-pdfs

一部のプロバイダー（OpenAI、Anthropic Claude、Google Gemini）はPDFアップロードに対応しています。`Image/PDF`ボタンをクリックしてPDFファイルを添付します。

?> **Anthropic Claude**: Claudeのモデルを用いたアプリでは、PDFを直接アップロードしてAIエージェントに内容を認識させることが可能です。

<!-- SCREENSHOT: PDFアップロード後のチャット - ユーザーがPDFファイルをアップロードし、AIがPDFの内容について回答している様子 -->

PDF は添付したメッセージと一緒に送られ、その後のターンでも会話の履歴の中に残ります。

## 拡張ドキュメント形式のアップロード :id=uploading-extended-documents

一部のOpenAIモデルは、File Inputs APIを通じて拡張されたドキュメント形式をサポートしています。そうしたモデルでは、ボタンが`Attach file`になり、画像やPDFに加えて以下の形式を受け付けます（50 MB まで、PDF は 35 MB まで）：

- スプレッドシート: `.xlsx`, `.csv`
- ドキュメント: `.docx`, `.pptx`, `.txt`, `.md`
- データ/マークアップ: `.json`, `.html`, `.xml`

ファイルはセッションごとにキャッシュされるため、同じドキュメントは複数ターンにわたって参照されても OpenAI へのアップロードは1回のみです。

Responses APIを使用するモデルでは、ローカルファイルのアップロードの代わりに、モーダルダイアログでファイルのURLを直接入力することもできます。

## 動画と音声のファイルの添付 :id=attaching-video-audio

動画を分析するアプリや音声を文字起こしするアプリでは、`Image` ボタンで動画（MP4、M4V、MOV、WebM、MKV、AVI）や音声（MP3、M4A、WAV、OGG、Opus、FLAC、AAC、WebM）のファイルも添付できます。ファイルはチャットのフォルダにアップロードされ、メッセージを送るまでメッセージ欄の下に表示されます。Video Describer は動画を、Speech Draft Helper は音声のファイルを受け付けます。

## 文書ファイルからのテキスト読み込み :id=reading-text-from-document-files

`Text from file` ボタンをクリックすると、文書ファイルを選択するダイアログが表示されます。選択したファイルの内容がテキストエリアに読み込まれます。読み込みが可能なファイル形式はPDF、Wordファイル（`.docx`）、Excelファイル（`.xlsx`）、PowerPointファイル（`.pptx`）、さまざまなテキストファイル（`.txt`, `.md`, `.html`, etc）です。

<!-- SCREENSHOT: ファイルからテキスト抽出ダイアログ - ファイル選択ダイアログが表示され、各種文書ファイル形式が選択可能な様子 -->

## URL からのテキスト読み込み :id=reading-text-from-urls

`Text from URL` ボタンをクリックすると、URL を入力するダイアログが表示されます。URL を入力すると、その URL にあるコンテンツが可能な範囲で読み出され、Markdown形式でテキストエリアに読み込まれます。

<!-- SCREENSHOT: URLからテキスト抽出ダイアログ - URL入力フィールドとOK/Cancelボタンが表示されている様子 -->

## 音声入力 :id=speech-input

?> 音声入力はChrome、Edge、Safariでサポートされています。

音声入力を行う場合は、`Speech Input` ボタンをクリックして音声入力を開始し、`Stop` ボタンをクリックして音声入力を終了します。音声入力が終了すると、Speech-to-Text API を通じて音声がテキストに変換され、テキストエリアに表示されます。iPhone と iPad では音声入力は使えません。

[Live Conversation](../apps/chat-apps.md#live-conversation) はこの経路を使いません。テキスト入力も `Speech Input` ボタンもなく、セッション中はマイクが常時ストリーミングされます。

<!-- SCREENSHOT: 音声入力中の画面 - Speech Inputボタンの代わりにStopボタンが表示され、音声波形が動いている様子 -->

値を返す音声認識モデルでは、音声入力後に `Last Speech-to-Text p-value` が表示されます。これは認識結果の信頼度を 0 から 1 の範囲で示す指標で、1 に近いほど信頼度が高いことを意味します。

<!-- SCREENSHOT: 音声入力後のp-value表示 - テキストエリア上部に「p-value: 0.95」などの信頼度スコアが表示されている様子 -->

## 音声認識モデルの選択 :id=speech-to-text-model-selection

Web UIの Speech パネルで音声認識モデルを選択できます。複数のプロバイダーのモデルが利用可能です。一覧は[Speech パネル](/ja/basic-usage/web-interface.md)を参照してください（各モデルはプロバイダーのAPIキーが確認されると選択可能になります）。

## リアルタイムストリーミング音声認識 :id=realtime-streaming-transcription

Speech-to-Textモデルのドロップダウンで `GPT Realtime Whisper ⚡` を選択すると、ストリーミング音声認識モードが有効になります。⚡ の記号は録音中にライブで暫定的な認識結果（partial transcript）を返すモデルであることを示します。このモデルを選択した場合、`Speech Input` の挙動は通常のバッチ処理経路と次のように異なります。

- 話している間、累積された認識結果のライブプレビューが、メッセージ入力欄に**グレーの文字**として表示されます。プレビューは数百ミリ秒ごとに更新されます。
- 録音中もテキストエリアにタイピングを続けられます。グレーのプレビューはタイプしたカーソル位置の後ろに付き従う形で表示され、入力中の文字が partial で上書きされることはありません。
- `Stop` をクリックすると、確定した最終認識結果が、テキストエリアにそれまで入力していた内容の末尾に追記され、グレーのプレビューは消えます。
- `Easy submit` は、最終認識結果で 1 度だけメッセージを送ります。途中の partial で送信が発火することはありません。

<!-- SCREENSHOT: リアルタイムストリーミング中のメッセージ入力欄 — 発話中、テキストエリアの中にグレーの文字で partial が表示されている様子 -->

**ストリーミングモードとバッチモードの使い分け。** ストリーミングモードは長い発話中に即時の視覚フィードバックを得られるため、ライブメモやディクテーションの用途に適しています。バッチ処理経路は短い発話に対しては費用効率が良く、ドロップダウン上の他のモデルはすべてこの経路を使用します。

**コストについて。** リアルタイム音声認識は OpenAI によって音声の分数単位で課金され、同社のバッチ転写よりも単価が高くなります。ドロップダウン上の他のモデルはそれぞれのプロバイダーが課金するため、現在の料金は各プロバイダーの料金ページを参照してください。

**プロバイダー対応状況。** リアルタイムストリーミング音声認識は OpenAI でだけ利用できます。ドロップダウン上の他のSTTモデルはバッチ経路を使用します。なおこの音声認識機能は、[Live Conversation](../apps/chat-apps.md#live-conversation) の speech-to-speech 会話とは別の機能です（Live Conversation は OpenAI・xAI・Gemini で利用できます）。

!> **Privacy Filter との関係。** `Speech Input` で取り込んだ音声は、Privacy Filter のマスキングが適用される前に、選択中の Speech-to-Text モデルのプロバイダーへ送信されて転写されます。Privacy Filter は転写後の**テキスト**を LLM に送る段階でのみ動作するため、音声そのものをマスクすることはありません。そのプロバイダーに送りたくない個人情報を含む音声がある場合は、音声入力ではなくテキスト入力で送ってください。

## 音声合成の再生

**再生の操作**<br />
AIレスポンスの `Start TTS` のアイコンをクリックすると合成音声を聞けます。`Stop TTS` で再生が止まります（アイコンにポインタを重ねると名前が出ます）。

**Auto speech**<br />
Interaction パネルで `Auto speech` をオンにすると、AIレスポンスが自動的に読み上げられます。`Easy submit`と組み合わせると音声対話に便利です。
