# 基本アプリ

現在、以下の基本アプリが使用可能です。いずれかの基本アプリを選択し、パラメータを変更したり、初期プロンプトを書き換えたりすることで、AIエージェントの挙動を調整できます。調整した設定は、外部のJSONファイルにエクスポート／インポートできます。

基本アプリはOpenAIのモデルを使用します。OpenAI以外のモデルを使用する場合は、[言語モデル](language-models.md)を参照してください。

独自のアプリを作る方法については[アプリの開発](develop_apps.md)を参照してください。

?> 各アプリの説明の下のドロップダウンをクリックすると、アプリのソースコードが表示されます。ソースコードはMonadic Chatの[Githubレポジトリ](https://github.com/yohasebe/monadic-chat)の`main`ブランチでの最新版です。

## アシスタント

### Chat

![Chat app icon](./assets/icons/chat.png ':size=40')

 標準的なチャットアプリケーションです。ユーザーが入力したテキストに対して、AIが応答します。内容に応じた絵文字も表示されます。

<details>
<summary>chat_app.rb</summary>

[chat_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/chat/chat_app.rb ':include :type=code')

</details>

### Chat Plus

![Chat app icon](./assets/icons/chat.png ':size=40')

Chatアプリの拡張版で、"monadic" な振る舞いを示します。AIの回答の背後で下記の情報を保持し、随時更新します。

- reasoning: 回答の作成における動機づけと根拠など
- topics: ここまでの会話で取り上げられたトピック
- people: 会話に関連する人物
- notes: 会話で取り上げられた重要なポイント

<details>
<summary>chat_plus_app.rb</summary>

[chat_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/chat_plus/chat_plus_app.rb ':include :type=code')

</details>

### Voice Chat

![Voice Chat app icon](./assets/icons/voice-chat.png ':size=40')

OpenAIのWhisper API（音声認識）とブラウザの音声合成APIを用いて、音声でチャットを行うことができるアプリケーションです。初期プロンプトは基本的にChatアプリと同じです。Google Chrome、Microsoft Edgeなど、ブラウザのText to Speech APIが動作するWebブラウザが必要です。

![Voice input](./assets/images/voice-input-stop.png ':size=400')

音声入力中は波形が表示され、音声入力が終了すると、認識の「確らしさ」を示すp-value（0〜1の値）が表示されます。

![Voice p-value](./assets/images/voice-p-value.png ':size=400')

<details>
<summary>voice_chat_app.rb</summary>

![voice_chat_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/voice_chat/voice_chat_app.rb ':include :type=code')

</details>

### Wikipedia

![Wikipedia app icon](./assets/icons/wikipedia.png ':size=40')

基本的にChatと同じですが、言語モデルのカットオフ日時以降に発生したイベントに関する質問など、GPTが回答できない質問に対しては、Wikipediaを検索して回答します。問い合わせが英語以外の言語の場合、Wikipediaの検索は英語で行われ、結果は元の言語に翻訳されます。

<details>
<summary>wikipedia_app.rb</summary>

![wikipedia_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/wikipedia/wikipedia_app.rb ':include :type=code')

</details>

### Math Tutor

![Math Tutor app icon](./assets/icons/math.png ':size=40')

AIチャットボットが [MathJax](https://www.mathjax.org/) の数式表記を用いて応答するアプリケーションです。数式の表示が必要なやりとりを行うのに適しています。

!> LLMの数学的計算能力には制約があり、誤った結果が出力されることがあります。計算の正確性が求められる場合は、Code Interpreterアプリなどで実際に計算を行うことをお勧めします。

<details>
<summary>math_tutor_app.rb</summary>

![math_tutor_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/math_tutor/math_tutor_app.rb ':include :type=code')

</details>

### Second Opinion

![Second Opinion app icon](./assets/icons/second-opinion.png ':size=40')

その質問に対する回答を生成します。その際、その回答の妥当性を確認するために、AIエージェント自身が同じLLMモデルに質問を投げ、自身の回答と比較します。AIによる回答におけるハルシネーションや誤解を防ぐために、このアプリケーションを使用することができます。

<details>
<summary>second_opinion_app.rb</summary>

![second_opinion_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/second_opinion/second_opinion_app.rb ':include :type=code')

</details>

## 言語関連

### Language Practice

![Language Practice app icon](./assets/icons/language-practice.png ':size=40')

アシスタントの発話から会話が始まる語学学習アプリケーションです。アシスタントの発話は音声合成で再生されます。ユーザーは、Enterキーを押して発話入力を開始し、もう一度Enterキーを押して発話入力を終了します。

<details>
<summary>language_practice_app.rb</summary>

![language_practice_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/language_practice/language_practice_app.rb ':include :type=code')

</details>

### Language Practice Plus

![Language Practice Plus app icon](./assets/icons/language-practice-plus.png ':size=40')

アシスタントの発話から会話が始まる語学学習アプリケーションです。アシスタントの発話は音声合成で再生されます。ユーザーは、Enterキーを押して発話入力を開始し、もう一度Enterキーを押して発話入力を終了します。アシスタントは、通常の応答に加えて、言語的なアドバイスを含めます。言語的なアドバイスは、音声ではなくテキストとしてのみ提示されます。

<details>
<summary>language_practice_plus_app.rb</summary>

![language_practice_plus_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/language_practice_plus/language_practice_plus_app.rb ':include :type=code')

</details>

### Translate

![Translate app icon](./assets/icons/translate.png ':size=40')

ユーザーの入力テキストを別の言語に翻訳します。まず、AIアシスタントが翻訳先の言語を尋ねます。次に、ユーザーの入力テキストを指定された言語に翻訳します。特定の表現に関して、それらをどのように訳すかを指定したい場合は、入力テキストの該当箇所に括弧を付け、括弧内に翻訳表現を指定してください。

<details>
<summary>translate_app.rb</summary>

![translate_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/translate/translate_app.rb ':include :type=code')

</details>

### Voice Interpreter

![Voice Interpreter app icon](./assets/icons/voice-chat.png ':size=40')

ユーザーが音声入力で与えた内容を別の言語に翻訳し、音声合成で発話します。まず、アシスタントは翻訳先の言語を尋ねます。次に、入力されたテキストを指定された言語に翻訳します。

<details>
<summary>voice_interpreter_app.rb</summary>

![voice_interpreter_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/voice_interpreter/voice_interpreter_app.rb ':include :type=code')

</details>

## コンテンツ生成

### Novel Writer

![Novel Writer app icon](./assets/icons/novel.png ':size=40')

アシスタントと共同で小説を執筆するためのアプリケーションです。ユーザーのプロンプトに基づいてストーリーを展開し、一貫性と流れを維持します。AIエージェントは最初に、物語の舞台、登場人物、ジャンル、最終的な文章の量を尋ねます。その後、ユーザーが提供するプロンプトに基づいて、AIエージェントが物語を展開します。

<details>
<summary>novel_writer_app.rb</summary>

![novel_writer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

### Image Generator

![Image Generator app icon](./assets/icons/image-generator.png ':size=40')

説明に基づいて画像を生成するアプリケーションです。プロンプトが具体的でない場合や、英語以外の言語で書かれている場合は、改善されたプロンプトを返し、改善されたプロンプトで続行するかどうかを尋ねます。内部でDall-E 3 APIを使用しています。

画像は`Shared Folder`に保存されると共に、チャット上でも表示されます。

<details>
<summary>image_generator_app.rb</summary>

![image_generator_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/image_generator/image_generator_app.rb ':include :type=code')

</details>

### Mail Composer

![Mail Composer app icon](./assets/icons/mail-composer.png ':size=40')

アシスタントと共同でメールの草稿を作成するためのアプリケーションです。ユーザーの要望や指定に応じて、アシスタントがメールの草稿を作成します。

<details>
<summary>mail_composer_app.rb</summary>

![mail_composer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/mail_composer/mail_composer_app.rb ':include :type=code')

</details>

### Mermaid Grapher

![Mermaid Grapher app icon](./assets/icons/diagram-draft.png ':size=40')

[mermaid.js](https://mermaid.js.org/) を活用してデータを視覚化するアプリケーションです。任意のデータや指示文を入力すると、エージェントがフローチャートのMermaid コードを生成して画像を描画します。

<details>
<summary>flowchart_grapher_app.rb</summary>

![flowchart_grapher_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/mermaid_grapher/mermaid_grapher_app.rb ':include :type=code')

</details>

### Music Composer

![Music Composer app icon](./assets/icons/music.png ':size=40')

[ABC](https://en.wikipedia.org/wiki/ABC_notation)記法で簡単な楽譜を作成し、Midiで演奏するアプリケーションです。使用する楽器と音楽のジャンルやスタイルを指定します。

<details>
<summary>music_composer_app.rb</summary>

![music_composer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/music_composer/music_composer_app.rb ':include :type=code')

</details>

### Speech Draft Helper

![Speech Draft Helper app icon](./assets/icons/speech-draft-helper.png ':size=40')

このアプリでは、AIエージェントにスピーチのドラフト作成を依頼することができます。ドラフトを一から作成することもできますし、既存のドラフトを、テキスト文字列、Wordファイル、PDFファイルの形で提出することもできます。AIエージェントはそれらを分析し、修正版を返します。また、必要であれば、スピーチをより魅力的で効果的なものにするための改善案やヒントを提供します。スピーチのmp3ファイルを提供することもできます。

<details>
<summary>speech_draft_helper_app.rb</summary>

![speech_draft_helper_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/speech_draft_helper/speech_draft_helper_app.rb ':include :type=code')

</details>

## コンテンツ分析

### Video Describer

![Video Describer app icon](./assets/icons/video.png ':size=40')

動画コンテンツを分析し、その内容を説明するアプリケーションです。AIが動画コンテンツを分析し中で何が起こっているのかを詳細に説明します。

アプリ内部で動画からフレームを抽出し、それらをbase64形式のPNG画像に変換します。さらに、ビデオから音声データを抽出し、MP3ファイルとして保存します。これらに基づいてAIが動画ファイルに含まれる視覚および音声情報の全体的な説明を行います。

このアプリを使用するには、ユーザーは動画ファイルを`Shared Folder`に格納して、ファイル名を伝える必要があります。また、フレーム抽出のための秒間フレーム数（fps）を指定する必要があります。総フレーム数が50を超える場合はビデオ全体から50フレームが選択・抽出されます。

<details>
<summary>video_describer_app.rb</summary>

![video_describer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/video_describer/video_describer_app.rb ':include :type=code')

</details>

### PDF Navigator

![PDF Navigator app icon](./assets/icons/pdf-navigator.png ':size=40')

PDFファイルを読み込み、その内容に基づいてユーザーの質問に答えるアプリケーションです。`Upload PDF` ボタンをクリックしてファイルを指定してください。ファイルの内容はmax_tokensの長さのセグメントに分割され、セグメントごとにテキスト埋め込みが計算されます。ユーザーからの入力を受け取ると、入力文のテキスト埋め込み値に最も近いテキストセグメントがユーザーの入力値とともにGPTに渡され、その内容に基づいて回答が生成されます。

?> PDF ファイルからのテキスト抽出には、[PyMuPDF](https://pymupdf.readthedocs.io/en/latest/) ライブラリが使用されます。抽出したテキストと埋め込みデータは [PGVector](https://github.com/pgvector/pgvector) データベースに保存されます。

![PDF button](./assets/images/app-pdf.png ':size=700')

![Import PDF](./assets/images/import-pdf.png ':size=400')

![PDF DB Panel](./assets/images/monadic-chat-pdf-db.png ':size=400')

<details>
<summary>pdf_navigator_app.rb</summary>

![pdf_navigator_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/pdf_navigator/pdf_navigator_app.rb ':include :type=code')

</details>

### Content Reader

![Content Reader app icon](./assets/icons/document-reader.png ':size=40')

提供されたファイルやWeb URLの内容を調べて説明するAIチャットボットを特徴とするアプリケーションです。説明は、わかりやすく、初心者にも理解しやすいように提示されます。ユーザーは、プログラミングコードを含む、さまざまなテキストデータを含むファイルやURLをアップロードすることができます。プロンプトメッセージにURLが記載されている場合、アプリは自動的にコンテンツを取得し、GPTとの会話にシームレスに統合します。

AIに読み込ませたいファイルを指定するには、`Shared Folder` にファイルを保存して、Userメッセージの中でファイル名を指定してください。AIがファイルの場所を見つけられない場合は、ファイル名を確認して、現在のコード実行環境から利用可能であることをメッセージ中で伝えてください。

`Shared Folder`から、下記のフォーマットのファイルを読み込むことができます。

- PDF
- Microsoft Word (docx)
- Microsoft PowerPoint (pptx)
- Microsoft Excel (xlsx)
- CSV
- Text (txt)

PNGやJPEGなどの画像ファイルを読み込んで、その内容を認識・説明させることもできます。また、MP3などの音声ファイルを読み込んで、内容をテキストに書き出すことも可能です。

<details>
<summary>content_reader_app.rb</summary>

![content_reader_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/content_reader/content_reader_app.rb ':include :type=code')

</details>

## コード生成

### Code Interpreter

![Code Interpreter app icon](./assets/icons/code-interpreter.png ':size=40')

AIにプログラムコードを作成・実行させるアプリケーションです。プログラムの実行には、Dockerコンテナ内のPython環境が使用されます。実行結果として得られたテキストデータや画像は`Shared Folder`に保存されると共に、チャット上でも表示されます。

AIに読み込ませたいファイル（PythonコードやCSVデータなど）がある場合は、`Shared Folder` にファイルを保存して、Userメッセージの中でファイル名を指定してください。AIがファイルの場所を見つけられない場合は、ファイル名を確認して、現在のコード実行環境から利用可能であることを伝えてください。

<details>
<summary>code_interpreter_app.rb</summary>

![code_interpreter_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/code_interpreter/code_interpreter_app.rb ':include :type=code')

</details>

下記の言語モデルでもCode Interpreterアプリが利用可能です。

- Anthropic Claude

### Coding Assistant

![Coding Assistant app icon](./assets/icons/coding-assistant.png ':size=40')

これはコンピュータプログラムコードを書くためのアプリケーションです。プロフェッショナルなソフトウェアエンジニアとして設定が与えられたAIと対話することができます。ユーザーからのプロンプトを通じて様々なな質問に答え、コードを書き、適切な提案を行い、役立つアドバイスを提供します。

?> Code InterpreterアプリはDocker上のPython環境でコードを実行することができますが、Coding Assistantアプリはコードの生成に特化しており、コードの実行は行いません。長いコードはいくつかの断片に分割し、分割点ごとに続きを表示するかをユーザーに問い合わせます。

<details>
<summary>coding_assistant_app.rb</summary>

[coding_assistant_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/coding_assistant/coding_assistant_app.rb ':include :type=code')

</details>

下記の言語モデルでもCoding Assistantアプリが利用可能です。

- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI

### Jupyter Notebook

![Jupyter Notebook app icon](./assets/icons/jupyter-notebook.png ':size=40')

AIがJupyter Notebookを作成して、ユーザーからのリクエストに応じてセルを追加し、セル内のコードを実行するアプリケーションです。コードの実行には、Dockerコンテナ内のPython環境が使用されます。作成されたNotebookは`Shared Folder`に保存されます。

?> Jupyterノートブックを実行するためのJupyterLabサーバーの起動と停止は、AIエージェントに自然言語で依頼する他に、Monadic Chatコンソールパネルのメニューからも行うことができます（`Start JupyterLab`, `Stop JupyterLab`）。
<br /><br />![Action menu](./assets/images/action-menu.png ':size=160')

<details>

<summary>jupyter_notebook_app.rb</summary>

![jupyter_notebook_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/jupyter_notebook/jupyter_notebook_app.rb ':include :type=code')

</details>

下記の言語モデルでもJupyter Notebookアプリが利用可能です。

- Anthropic Claude

