# メッセージ入力

Monadic Chat コンソールでサーバーを起動し、Web インターフェイスでアプリの選択と各種の設定行った後に `Start Session` ボタンをクリックする以下のような画面が表示されます。

![](../assets/images/monadic-chat-message-input.png ':size=700')

テキストエリアにメッセージを入力し、`Send` ボタンをクリックすると、メッセージが送信されます。音声入力を行う場合は、`Speech Input` ボタンをクリックして音声入力を開始し、`Stop` ボタンをクリックして音声入力を終了すると、Speech-to-Text API を通じて音声がテキストに変換され、テキストエリアに表示されます。

?> 音声入力と音声合成を使って AI エージェントとのチャットをスムーズに行うためには、System Settings画面で `Auto Speech` と `Easy Submit` をオンにしておくと便利です。[Voice Chat](./basic-apps.md#voice-chat)アプリではこれらがデフォルトで有効になっています。

?> `Role` セレクタは、メッセージの役割を選択するためのものです。通常は `User` を選択しますが、`Assistant` や `System` を選択することで、チャットのコンテクストを追加・加工することができます。詳しくは [FAQ](../faq/faq-user-interface.md) を参照してください。

## 画像のアップロード :id=uploading-images

画像アップロードは、ビジョン機能を持つモデル（OpenAI、Anthropic Claude、xAI Grok、Google Gemini、Mistral、Perplexity）で利用できます。

`Image`（PDFもサポートするモデルでは`Image/PDF`）をクリックして画像を選択します。対応形式：JPG、JPEG、PNG、GIF、WebP

![](../assets/images/attach-image.png ':size=400')

画像をアップロードすると、画像認識が行われ、プロンプトのテキストでの指示に応じてAIエージェントが画像に関する情報を提供します（画像認識ができないモデルもあります）。

![](../assets/images/monadic-chat-message-with-pics.png ':size=700')

## PDF のアップロード :id=uploading-pdfs

一部のプロバイダー（OpenAI、Anthropic Claude、Google Gemini）はPDFアップロードに対応しています。`Image/PDF`ボタンをクリックしてPDFファイルを添付します。

?> **Anthropic Claude**: Claudeのモデルを用いたアプリでは、PDFを直接アップロードしてAIエージェントに内容を認識させることが可能です。

![](../assets/images/monadic-chat-chat-about-pdf.png ':size=700')

一度アップロードすると、削除`×`ボタンをクリックするまで毎回のメッセージでPDFが送信されます。同じPDFを繰り返し参照する場合は、システム設定で`Prompt Caching`を有効にするとAPIコストを削減できます。

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

コンソール設定画面でSpeech-to-Textモデルを選択できます。OpenAIおよびGeminiのモデルが利用可能です。

## 音声合成の再生

**再生ボタン**<br />
AIレスポンスの`再生`ボタンをクリックすると合成音声を聞くことができます。`停止`をクリックすると再生が停止します。

**自動音声再生（Auto Speech）**<br />
チャット対話コントロールで有効にすると、AIレスポンスが自動的に読み上げられます。`Easy Submit`と組み合わせると音声対話に便利です。

## プロバイダー固有の機能

### OpenAI Predicted Outputs

?> **OpenAI**: OpenAIのモデルを用いたアプリでは、プロンプトの中で `__DATA__` をセパレーターとして使用することで、AIエージェントへの指示と、修正・加工してもらいたいデータを区別して示すことができます。これによりレスポンスを高速化するとともにトークン数を削減できます（[Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)）。
