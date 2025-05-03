# メッセージ入力

Monadic Chat コンソールでサーバーを起動し、Web インターフェイスでアプリの選択と各種の設定行った後に `Start Session` ボタンをクリックする以下のような画面が表示されます。

![](../assets/images/monadic-chat-message-input.png ':size=700')

テキストエリアにメッセージを入力し、`Send` ボタンをクリックすると、メッセージが送信されます。音声入力を行う場合は、`Speech Input` ボタンをクリックして音声入力を開始し、`Stop` ボタンをクリックして音声入力を終了すると、Speech-to-Text API を通じて音声がテキストに変換され、テキストエリアに表示されます。

?> 音声入力と音声合成を使って AI エージェントとのチャットをスムーズに行うためには、System Settings画面で `Auto Speech` と `Easy Submit` をオンにしておくと便利です。[Voice Chat](./basic-apps.md#voice-chat)アプリではこれらがデフォルトで有効になっています。

?> `Role` セレクタは、メッセージの役割を選択するためのものです。通常は `User` を選択しますが、`Assistant` や `System` を選択することで、チャットのコンテクストを追加・加工することができます。詳しくは [FAQ](../faq/faq-user-interface.md) を参照してください。

## 画像のアップロード :id=uploading-images

以下のモデルでは画像のアップロードがサポートされています。

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI (Pixtral)

`Image` をクリックすると、メッセージに添付する画像を選択するダイアログが表示されます。

![](../assets/images/attach-image.png ':size=400')

画像をアップロードすろと、画像認識が行われ、プロンプトのテキストでの指示に応じてAIエージェントが画像に関する情報を提供します（画像認識ができないモデルもあります）。

![](../assets/images/monadic-chat-message-with-pics.png ':size=700')

## PDF のアップロード :id=uploading-pdfs

Anthropic の Sonnet モデル、OpenAI の gpt-4.1、gpt-4.1-mini、gpt-4.1-nano、gpt-4o、gpt-4o-mini、o1 モデル、および Google Gemini モデルでは、PDF のアップロードもサポートされています。`Image/PDF` をクリックすると、メッセージに添付する PDF ファイルを選択するダイアログが表示されます。

![](../assets/images/monadic-chat-pdf-attachment.png ':size=400')

画像の場合と同様に、PDF ファイルをアップロードすると、PDF の内容が認識され、プロンプトのテキストでの指示に応じてAIエージェントが PDF に関する情報を提供します。

![](../assets/images/monadic-chat-chat-about-pdf.png ':size=700')

チャットの中で継続してPDFの内容についてのやり取りを行うためには、毎回のメッセージ入力で同じ PDF をアップロードする必要があります。セッション中にある PDF を一度アップロードすると、Monadic Chat はセッション終了までの間、毎回、AI エージェントにその PDF を送信します。その際、System Settings画面で `Prompt Caching` を有効にしている場合、同じ PDF に対するプロンプトがキャッシュされ、API の使用量を節約することができます。その PDF についてのやり取りを終了する場合は、削除 `×` ボタンをクリックして、PDF をクリアします。

## 文書ファイルからのテキスト読み込み :id=reading-text-from-document-files

`From file` ボタンをクリックすると、文書ファイルを選択するダイアログが表示されます。選択したファイルの内容がテキストエリアに読み込まれます。読み込みが可能なファイル形式はPDF、Wordファイル（`.docx`）、Excelファイル（.`xlsx`）、PowerPointファイル（`.pptx`）、さまざまなテキストファイル（`.txt`, `.md`, `.html`, etc）です。

![](../assets/images/monadic-chat-extract-from-file.png ':size=400')

## URL からのテキスト読み込み :id=reading-text-from-urls

`From URL` ボタンをクリックすると、URL を入力するダイアログが表示されます。URL を入力すると、その URL にあるコンテンツが可能な範囲で読み出され、Markdown形式でテキストエリアに読み込まれます。

![](../assets/images/monadic-chat-extract-from-url.png ':size=400')

## 音声入力 :id=speech-input

?> 音声入力はChrome、Edge、Safariでサポートされています。

音声入力を行う場合は、`Speech Input` ボタンをクリックして音声入力を開始し、`Stop` ボタンをクリックして音声入力を終了します。音声入力が終了すると、Speech-to-Text API を通じて音声がテキストに変換され、テキストエリアに表示されます。

![](../assets/images/voice-input-stop.png ':size=400')

音声入力後には、音声入力の信頼度を示す `p-value` が表示されます。`p-value` は音声入力の信頼度を示す指標で、0 から 1 の範囲で表されます。`p-value` が 1 に近いほど、音声入力の信頼度が高いことを示します。

![](../assets/images/voice-p-value.png ':size=400')

## 音声認識モデルの選択 :id=speech-to-text-model-selection

設定画面でSpeech-to-Text (STT)モデルを選択できます。Monadic Chatは以下のOpenAI STTモデルをサポートしています:
- whisper-1
- gpt-4o-mini-transcribe
- gpt-4o-transcribe

新しいモデル（gpt-4o-mini-transcribe、gpt-4o-transcribe）は精度と文字起こし品質が向上しています。Monadic Chatは各STTモデルに最適な音声フォーマットを自動的に選択し、最良の文字起こし結果を確保します。
