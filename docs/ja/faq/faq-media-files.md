# FAQ：メディアファイルの送信

**Q**: テキスト以外のデータをAIエージェントに送信することはできますか？

**A**: はい、選択したモデルが対応している場合、`Image`ボタンをクリックして画像（JPG、JPEG、PNG、GIF、WebP）をアップロードすることができます。繰り返し行うことで複数の画像をアップロードすることもできます。Anthropic Claude、OpenAI の gpt-4o、gpt-4o-mini、o1 モデル、または Google Gemini モデルを使用している場合は、画像だけでなくPDFファイルもアップロードできます。

その他のメディアについては、共有フォルダにファイルを配置し、ファイル名（パスは不要）をメッセージボックスで指定してAIエージェントに伝えてください。選択しているアプリが対応している場合、AIエージェントはファイルを読み込んで処理します。

次の基本アプリはファイルの読み込みに対応しています。

- Code Interpreter<br />PythonスクリプトやCSVを含む各種のテキストファイル、Microsoft Officeファイル、オーディオファイル（MP3, WAV）
- Content Reader<br />テキストファイル、PDFファイル、Microsoft Officeファイル、オーディオファイル（MP3, WAV）
- PDF Reader<br />PDFファイル
- Video Description<br />動画ファイル（MP4, MOV）

`Speech Input`ボタンをクリックして音声入力を行うこともできます。音声入力はSpeech-to-Text APIを使用しており、すべてのアプリで利用可能です。

---

**Q**: PDFの内容について AI エージェントに質問することはできますか？

**A**: はい、いくつかのやり方があります。[`PDF Navigator`](../basic-usage/basic-apps.md#pdf-navigator) アプリでは、提供された PDF の単語埋め込みを PGVector データベースに格納して、RAG（Retrieval-Augmented Generation）の手法を用いる形で AI に回答させることができます。[`Code Interpreter`](../basic-usage/basic-apps.md#code-interpreter) や [`Content Reader`](../basic-usage/basic-apps.md#content-reader) アプリでは、PDF ファイルを Python コンテナ上の MuPDF4LLM で Markdown 形式に変換して、その内容を AI エージェントに読み込ませて、その内容に関する質問ができるようになっています。

上記はいずれも OpenAIの gpt-4 系列モデルを使用しています。その他のモデルを使用する場合は、`Code` 対応のアプリ（`Anthropic Claude (Code)` など）の場合、`Code Interpreter` と同様の仕組みで PDF ファイルを読み込ませることができます。

また、Anthropic Claude、OpenAI の gpt-4.1、gpt-4.1-mini、gpt-4.1-nano、gpt-4o、gpt-4o-mini、o1 モデル、または Google Gemini モデルを用いたアプリでは、テキスト入力ボックスの下にある `Import Image/PDF` ボタンをクリックして、PDF ファイルを直接アップロードして、内容について AI エージェントに質問することができます。詳しくは [PDF のアップロード](../basic-usage/message-input.md#pdf-のアップロード)を参照してください。

