# メッセージ入力

Monadic Chat コンソールでサーバーを起動し、Web インターフェイスでアプリの選択と各種の設定行った後に `Start Session` ボタンをクリックする以下のような画面が表示されます。

![](./assets/images/monadic-chat-message-input.png ':size=700')

テキストエリアにメッセージを入力し、`Send` ボタンをクリックすると、メッセージが送信されます。音声入力を行う場合は、`Voice Input` ボタンをクリックして音声入力を開始し、`Stop` ボタンをクリックして音声入力を終了すると、Whisper API を通じて音声がテキストに変換され、テキストエリアに表示されます。

?> `Role` セレクタは、メッセージの役割を選択するためのものです。通常は `User` を選択しますが、`Assistant` や `System` を選択することで、チャットのコンテクストをを追加・加工することができます。詳しくは [FAQ](/ja/faq) を参照してください。

## 画像のアップロード

`Upload Image` をクリックすると、メッセージに添付する画像を選択するダイアログが表示されます。

![](./assets/images/monadi-chat-image-attachment.png ':size=400')

画像をアップロードすろと、画像認識が行われ、プロンプトのテキストでの指示に応じてAIエージェントが画像に関する情報を提供します（画像認識ができないモデルもあります）。

![](./assets/images/monadic-chat-message-with-pics.png ':size=700')

## PDF のアップロード

Anthropic の Sonnet モデルでは、画像の他に PDF のアップロードもサポートされています。`Upload Image/PDF` をクリックすると、メッセージに添付する PDF ファイルを選択するダイアログが表示されます。

![](./assets/images/monadi-chat-pdf-attachment.png ':size=400')

画像の場合と同様に、PDF ファイルをアップロードすると、PDF の内容が認識され、プロンプトのテキストでの指示に応じてAIエージェントが PDF に関する情報を提供します。

![](./assets/images/monadic-chat-chat-about-pdf.png ':size=700')

チャットの中で継続してPDFの内容についてのやり取りを行うためには、毎回のメッセージ入力で同じ PDF をアップロードする必要があります。セッション中にある PDF を一度アップロードすると、Monadic Chat はセッション終了までの間、毎回、AI エージェントにその PDF を送信します。その際、Web 設定画面で `Prompt Caching` を有効にしている場合、同じ PDF に対するプロンプトがキャッシュされ、API の使用量を節約することができます。その PDF についてのやり取りを終了する場合は、削除 `×` ボタンをクリックして、PDF をクリアします。