# FAQ：メディアファイルの送信

##### Q: テキスト以外のデータをAIエージェントに送信することはできますか？ :id=sending-non-text-data

**A**: はい。ファイル（画像、PDF、文書、音声、動画）を[作業画面](../basic-usage/web-interface.md#work-screen)に置いてください。画像を読めるモデルなら、質問に必要なときに AI がそれを見ます。[AI に渡すファイル](../basic-usage/message-input.md#files-for-the-ai)を参照してください。

その他のメディアについては、共有フォルダにファイルを配置し、ファイル名（パスは不要）をメッセージボックスで指定してAIエージェントに伝えてください。選択しているアプリが対応している場合、AIエージェントはファイルを読み込んで処理します。

次の基本アプリはファイルの読み込みに対応しています。

- Code Interpreter<br />PythonスクリプトやCSVを含むテキストファイル、PDF、Microsoft Officeファイル。音声など、そのほかのファイルは Python のコードで処理
- Knowledge Base<br />**書庫** のタブの **ファイルを読み込み** ボタンから PDF / Microsoft Office (.docx / .xlsx / .pptx) / Markdown / ソースコードファイルをインポート可能
- Video Describer<br />動画ファイル（MP4、M4V、MOV、WebM、MKV、AVI）

`Speech Input`ボタンをクリックして音声入力を行うこともできます。音声入力はSpeech-to-Text APIを使用しており、すべてのアプリで利用可能です。

---

##### Q: PDFの内容について AI エージェントに質問することはできますか？ :id=pdf-content-questions

**A**: はい、いくつかのやり方があります。サイドバーの **書庫** のタブ（[Knowledge Base](../apps/knowledge-base.md)）で **ファイルを読み込み** から PDF をプロジェクト全体のベクトルデータベースに取り込むと、Knowledge Base を検索するアプリが RAG（Retrieval-Augmented Generation）の手法で回答します。[`Code Interpreter`](../apps/coding-apps.md#code-interpreter) アプリでは、PDF ファイルを Markdown 形式に変換して、その内容を AI エージェントに読み込ませて、その内容に関する質問ができるようになっています。

PDF を[作業画面](../basic-usage/web-interface.md#work-screen)に置いて、内容について AI エージェントに質問することもできます。AI はその文字を読み、PDF を読める Anthropic Claude、OpenAI、Google Gemini のモデルには PDF 全体がそのまま渡されます。詳しくは [AI に渡すファイル](../basic-usage/message-input.md#files-for-the-ai)を参照してください。

