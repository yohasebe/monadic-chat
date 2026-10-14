# FAQ：メディアファイルの送信

##### Q: テキスト以外のデータをAIエージェントに送信することはできますか？ :id=sending-non-text-data

**A**: はい、選択したモデルが対応している場合、メッセージ入力欄の下のボタンで画像（JPG、JPEG、PNG、GIF、WebP）を添付できます。1 つのメッセージに 5 枚までです。ボタンの名前はモデルによって変わります：`Image`、PDF も扱えるモデル（Anthropic Claude、OpenAI、Google Gemini のビジョン対応のモデル）では `Image/PDF`、Office の文書や CSV なども扱える OpenAI のモデルでは `Attach file` です。Video Describer と Speech Draft Helper では、同じボタンで動画や音声のファイルを添付できます。

その他のメディアについては、共有フォルダにファイルを配置し、ファイル名（パスは不要）をメッセージボックスで指定してAIエージェントに伝えてください。選択しているアプリが対応している場合、AIエージェントはファイルを読み込んで処理します。

次の基本アプリはファイルの読み込みに対応しています。

- Code Interpreter<br />PythonスクリプトやCSVを含むテキストファイル、PDF、Microsoft Officeファイル。音声など、そのほかのファイルは Python のコードで処理
- Knowledge Base<br />Browse モーダルの **Import file** ボタンから PDF / Microsoft Office (.docx / .xlsx / .pptx) / Markdown / ソースコードファイルをインポート可能
- Video Describer<br />動画ファイル（MP4、M4V、MOV、WebM、MKV、AVI）

`Speech Input`ボタンをクリックして音声入力を行うこともできます。音声入力はSpeech-to-Text APIを使用しており、すべてのアプリで利用可能です。

---

##### Q: PDFの内容について AI エージェントに質問することはできますか？ :id=pdf-content-questions

**A**: はい、いくつかのやり方があります。[`Knowledge Base`](../apps/knowledge-base.md) アプリでは **Import file** から PDF をプロジェクト全体のベクトルデータベースに取り込み、RAG（Retrieval-Augmented Generation）の手法で AI に回答させることができます。[`Code Interpreter`](../apps/coding-apps.md#code-interpreter) アプリでは、PDF ファイルを Markdown 形式に変換して、その内容を AI エージェントに読み込ませて、その内容に関する質問ができるようになっています。

また、Anthropic Claude、OpenAI、または Google Gemini のビジョン機能対応モデルを用いたアプリでは、テキスト入力ボックスの下にある `Image/PDF` ボタンをクリックして、PDF ファイルを直接アップロードして、内容について AI エージェントに質問することができます。このボタンは、対応モデルを使用している場合に動的にPDFアップロードを許可します。詳しくは [PDF のアップロード](../basic-usage/message-input.md#uploading-pdfs)を参照してください。

