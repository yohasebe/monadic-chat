# 基本アプリ

現在、以下の基本アプリが使用可能です。いずれかの基本アプリを選択し、パラメータを変更したり、初期プロンプトを書き換えたりすることで、AIエージェントの挙動を調整できます。調整した設定は、外部のJSONファイルにエクスポート／インポートできます。

基本アプリはOpenAIのモデルを使用します。OpenAI以外のモデルを使用する場合は、[言語モデル](./language-models.md)を参照してください。

独自のアプリを作る方法については[アプリの開発](../advanced-topics/develop_apps.md)を参照してください。

## モデル対応状況 :id=app-availability

以下の表は、各アプリケーションがどのAIモデルプロバイダで利用可能かを示しています。アプリの説明で特に記載がない場合は、OpenAIモデルのみで利用可能です。

| アプリ | OpenAI | Claude | Cohere | DeepSeek | Google Gemini | xAI Grok | Mistral | Perplexity |
|-------|:------:|:------:|:------:|:--------:|:------:|:----:|:-------:|:----------:|
| Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Chat Plus | ✅ | | | | | | | |
| Voice Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Wikipedia | ✅ | | | | | | | |
| Math Tutor | ✅ | | | | | | | |
| Second Opinion | ✅ | | | | | | | |
| Research Assistant | ✅ | ✅ | ✅ | | ✅ | ✅ | ✅ | ✅ |
| Language Practice | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Language Practice Plus | ✅ | | | | | | | |
| Translate | ✅ | | | | | | | |
| Voice Interpreter | ✅ | | | | | | | |
| Novel Writer | ✅ | | | | | | | |
| Image Generator | ✅ | | | | ✅ | ✅ | | |
| Mail Composer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mermaid Grapher | ✅ | | | | | | | |
| DrawIO Grapher | ✅ | ✅ | | | | | | |
| Speech Draft Helper | ✅ | | | | | | | |
| Video Describer | ✅ | | | | | | | |
| PDF Navigator | ✅ | | | | | | | |
| Content Reader | ✅ | | | | | | | |
| Code Interpreter | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | | |
| Coding Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Jupyter Notebook | ✅ | ✅ | | | | | | |

## アシスタント :id=assistant

### Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

標準的なチャットアプリケーションです。ユーザーが入力したテキストに対して、AIが応答します。内容に応じた絵文字も表示されます。

下記の言語モデルでChatアプリが利用可能です。

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- DeepSeek

### Chat Plus

![Chat app icon](../assets/icons/chat-plus.png ':size=40')

Chatアプリの拡張版で、"monadic" な振る舞いを示します。AIの回答の背後で下記の情報を保持し、随時更新します。

- reasoning: 回答の作成における動機づけと根拠など
- topics: ここまでの会話で取り上げられたトピック
- people: 会話に関連する人物
- notes: 会話で取り上げられた重要なポイント

### Voice Chat :id=voice-chat

![Voice Chat app icon](../assets/icons/voice-chat.png ':size=40')

OpenAIのSpeech-to-Text API（音声認識）とブラウザの音声合成APIを用いて、音声でチャットを行うことができるアプリケーションです。初期プロンプトは基本的にChatアプリと同じです。このアプリは異なるAIモデルを使用して応答を生成できます。Google Chrome、Microsoft Edgeなど、ブラウザのText to Speech APIが動作するWebブラウザが必要です。

![Voice input](../assets/images/voice-input-stop.png ':size=400')

音声入力中は波形が表示され、音声入力が終了すると、認識の「確からしさ」を示すp-value（0〜1の値）が表示されます。

![Voice p-value](../assets/images/voice-p-value.png ':size=400')

下記の言語モデルでVoice Chatアプリが利用可能です。

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Cohere
- DeepSeek

### Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

基本的にChatと同じですが、言語モデルのカットオフ日時以降に発生したイベントに関する質問など、GPTが回答できない質問に対しては、Wikipediaを検索して回答します。問い合わせが英語以外の言語の場合、Wikipediaの検索は英語で行われ、結果は元の言語に翻訳されます。

### Math Tutor

![Math Tutor app icon](../assets/icons/math.png ':size=40')

AIチャットボットが [MathJax](https://www.mathjax.org/) の数式表記を用いて応答するアプリケーションです。数式の表示が必要なやりとりを行うのに適しています。

!> LLMの数学的計算能力には制約があり、誤った結果が出力されることがあります。計算の正確性が求められる場合は、Code Interpreterアプリなどで実際に計算を行うことをお勧めします。

### Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

その質問に対する回答を生成します。その際、その回答の妥当性を確認するために、AIエージェント自身が同じLLMモデルに質問を投げ、自身の回答と比較します。AIによる回答におけるハルシネーションや誤解を防ぐために、このアプリケーションを使用することができます。

### Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

アカデミックな研究や科学的研究をサポートするために設計されたアプリケーションで、インテリジェントな研究アシスタントとして機能します。Tavily APIを使用してウェブ検索を行い、ウェブページ、画像、音声ファイル、ドキュメントなどの情報を取得し、分析します。研究アシスタントは、信頼性の高い詳細な洞察、要約、説明を提供し、科学的な問い合わせを進めます。

下記の言語モデルでResearch Assistantアプリが利用可能です。

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity

?> このアプリの利用にはTavily API Keyが必要です。[Tavily](https://tavily.com/)のウェブサイトで取得できます。月に1,000回の無料リクエストが利用可能です。

## 言語関連 :id=language-related

### Language Practice

![Language Practice app icon](../assets/icons/language-practice.png ':size=40')

アシスタントの発話から会話が始まる語学学習アプリケーションです。アシスタントの発話は音声合成で再生されます。ユーザーは、Enterキーを押して発話入力を開始し、もう一度Enterキーを押して発話入力を終了します。

下記の言語モデルでLanguage Practiceアプリが利用可能です。

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- Cohere
- DeepSeek

### Language Practice Plus

![Language Practice Plus app icon](../assets/icons/language-practice-plus.png ':size=40')

アシスタントの発話から会話が始まる語学学習アプリケーションです。アシスタントの発話は音声合成で再生されます。ユーザーは、Enterキーを押して発話入力を開始し、もう一度Enterキーを押して発話入力を終了します。アシスタントは、通常の応答に加えて、言語的なアドバイスを含めます。言語的なアドバイスは、音声ではなくテキストとしてのみ提示されます。

### Translate

![Translate app icon](../assets/icons/translate.png ':size=40')

ユーザーの入力テキストを別の言語に翻訳します。まず、AIアシスタントが翻訳先の言語を尋ねます。次に、ユーザーの入力テキストを指定された言語に翻訳します。特定の表現に関して、それらをどのように訳すかを指定したい場合は、入力テキストの該当箇所に括弧を付け、括弧内に翻訳表現を指定してください。

### Voice Interpreter

![Voice Interpreter app icon](../assets/icons/voice-chat.png ':size=40')

ユーザーが音声入力で与えた内容を別の言語に翻訳し、音声合成で発話します。まず、アシスタントは翻訳先の言語を尋ねます。次に、入力されたテキストを指定された言語に翻訳します。

## コンテンツ生成 :id=content-generation

### Novel Writer

![Novel Writer app icon](../assets/icons/novel.png ':size=40')

アシスタントと共同で小説を執筆するためのアプリケーションです。ユーザーのプロンプトに基づいてストーリーを展開し、一貫性と流れを維持します。AIエージェントは最初に、物語の舞台、登場人物、ジャンル、最終的な文章の量を尋ねます。その後、ユーザーが提供するプロンプトに基づいて、AIエージェントが物語を展開します。

### Image Generator

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

説明に基づいて画像を生成するアプリケーションです。

OpenAIバージョンはgpt-image-1モデルを使用し、3つの主な操作をサポートしています：

1. **画像生成**：テキストの説明から新しい画像を作成
2. **画像編集**：テキストプロンプトとオプションのマスク画像を使用して既存の画像を修正
3. **画像バリエーション**：既存の画像の代替バージョンを生成

画像編集機能はgpt-image-1モデルでのみ利用可能です。

画像編集機能では、以下のことが可能です：
- 既存の画像をベースとして選択
- マスク画像を使用して修正する領域を指定（オプション）
- 変更内容のテキスト指示を提供
- 以下を含む出力オプションのカスタマイズ：
  - 画像サイズ（正方形、縦向き、横向き）
  - 品質レベル（標準、HD）
  - 出力形式（PNG、JPEG、WebP）
  - 背景タイプ（透明、不透明）
  - 圧縮レベル

### マスクの作成と使用

画像を編集する際、変更したい領域を指定するためのマスクを作成できます：

#### 元の画像

編集したい元画像の例：

![元画像](../assets/images/origina-image.jpg ':size=400')

#### マスクの作成

1. **マスクエディタを開く**：画像をアップロードした後、その画像をクリックして「マスクを作成」を選択
2. **マスクを描画**：ブラシツールを使用して、AIに編集してほしい領域（白い部分）を塗りつぶす
   - 消しゴムツールを使用してマスクの一部を削除
   - スライダーでブラシサイズを調整
   - 黒い領域は保存され、白い領域が編集される

![マスク編集](../assets/images/image-masking.png ':size=500')

3. **マスクを保存**：完了したら「マスクを保存」をクリック
4. **マスクを適用**：マスクは次の画像編集操作に自動的に適用される

マスクエディタには直感的な操作方法が用意されています：
- ブラシ/消しゴム切り替えボタン
- 調整可能なブラシサイズ
- マスククリアボタン
- マスクの下に元の画像のプレビュー表示

#### 編集後の結果

マスクを適用し編集指示を行った後、このような結果が得られます：

![編集結果](../assets/images/image-edit-result.png ':size=400')

編集プロセスでは、元の画像の構図や詳細を保存しながら、マスクで指定した領域のみに変更を適用します。

生成されたすべての画像は`Shared Folder`に保存されると共に、チャット上でも表示されます。

下記の言語モデルでImage Generatorアプリが利用可能です。

- OpenAI（gpt-image-1を使用） - 画像生成、編集、バリエーション生成に対応
- Google Gemini（Imagenを使用） - 画像生成に対応
- xAI Grok - 画像生成に対応

### Mail Composer

![Mail Composer app icon](../assets/icons/mail-composer.png ':size=40')

アシスタントと共同でメールの草稿を作成するためのアプリケーションです。ユーザーの要望や指定に応じて、アシスタントがメールの草稿を作成します。

下記の言語モデルでMail Composerアプリが利用可能です。

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- Cohere
- DeepSeek

### Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

[mermaid.js](https://mermaid.js.org/) を活用してデータを視覚化するアプリケーションです。任意のデータや指示文を入力すると、エージェントがフローチャートのMermaid コードを生成して画像を描画します。

### DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Draw.io ダイアグラムを作成するためのアプリケーションです。必要な図の仕様を説明すると、AIエージェントがDraw.io XMLファイルを生成し、共有フォルダに保存します。生成されたファイルはDraw.ioにインポートして編集することができます。フローチャート、UMLダイアグラム、ER図、ネットワーク図、組織図、マインドマップ、BPMNダイアグラム、ベン図、ワイヤフレームなど、様々な種類の図を作成できます。

下記の言語モデルでDrawIO Grapherアプリが利用可能です。

- OpenAI
- Anthropic Claude

### Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

このアプリでは、AIエージェントにスピーチのドラフト作成を依頼することができます。ドラフトを一から作成することもできますし、既存のドラフトを、テキスト文字列、Wordファイル、PDFファイルの形で提出することもできます。AIエージェントはそれらを分析し、修正版を返します。また、必要であれば、スピーチをより魅力的で効果的なものにするための改善案やヒントを提供します。スピーチのmp3ファイルを提供することもできます。

## コンテンツ分析 :id=content-analysis

### Video Describer

![Video Describer app icon](../assets/icons/video.png ':size=40')

動画コンテンツを分析し、その内容を説明するアプリケーションです。AIが動画コンテンツを分析し中で何が起こっているのかを詳細に説明します。

アプリ内部で動画からフレームを抽出し、それらをbase64形式のPNG画像に変換します。さらに、ビデオから音声データを抽出し、MP3ファイルとして保存します。これらに基づいてAIが動画ファイルに含まれる視覚および音声情報の全体的な説明を行います。

このアプリを使用するには、ユーザーは動画ファイルを`Shared Folder`に格納して、ファイル名を伝える必要があります。また、フレーム抽出のための秒間フレーム数（fps）を指定する必要があります。総フレーム数が50を超える場合はビデオ全体から50フレームが選択・抽出されます。

### PDF Navigator

![PDF Navigator app icon](../assets/icons/pdf-navigator.png ':size=40')

PDFファイルを読み込み、その内容に基づいてユーザーの質問に答えるアプリケーションです。`Upload PDF` ボタンをクリックしてファイルを指定してください。ファイルの内容はmax_tokensの長さのセグメントに分割され、セグメントごとにテキスト埋め込みが計算されます。ユーザーからの入力を受け取ると、入力文のテキスト埋め込み値に最も近いテキストセグメントがユーザーの入力値とともにGPTに渡され、その内容に基づいて回答が生成されます。

?> PDF ファイルからのテキスト抽出には、[PyMuPDF](https://pymupdf.readthedocs.io/en/latest/) ライブラリが使用されます。抽出したテキストと埋め込みデータは [PGVector](https://github.com/pgvector/pgvector) データベースに保存されます。ベクトルデータベース関連の実装に関する詳細は、[ベクトルデータベース](../docker-integration/vector-database.md)のドキュメントを参照してください。

![PDF button](../assets/images/app-pdf.png ':size=700')

![Import PDF](../assets/images/import-pdf.png ':size=400')

![PDF DB Panel](../assets/images/monadic-chat-pdf-db.png ':size=400')

### Content Reader

![Content Reader app icon](../assets/icons/document-reader.png ':size=40')

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

## コード生成 :id=code-generation

### Code Interpreter

![Code Interpreter app icon](../assets/icons/code-interpreter.png ':size=40')

AIにプログラムコードを作成・実行させるアプリケーションです。プログラムの実行には、Dockerコンテナ内のPython環境が使用されます。実行結果として得られたテキストデータや画像は`Shared Folder`に保存されると共に、チャット上でも表示されます。

AIに読み込ませたいファイル（PythonコードやCSVデータなど）がある場合は、`Shared Folder` にファイルを保存して、Userメッセージの中でファイル名を指定してください。AIがファイルの場所を見つけられない場合は、ファイル名を確認して、現在のコード実行環境から利用可能であることを伝えてください。

下記の言語モデルでCode Interpreterアプリが利用可能です。

- OpenAI
- Anthropic Claude
- Cohere
- DeepSeek
- Google Gemini
- xAI Grok

### Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

これはコンピュータプログラムコードを書くためのアプリケーションです。プロフェッショナルなソフトウェアエンジニアとして設定が与えられたAIと対話することができます。ユーザーからのプロンプトを通じて様々なな質問に答え、コードを書き、適切な提案を行い、役立つアドバイスを提供します。

?> Code InterpreterアプリはDocker上のPython環境でコードを実行することができますが、Coding Assistantアプリはコードの生成に特化しており、コードの実行は行いません。長いコードはいくつかの断片に分割し、分割点ごとに続きを表示するかをユーザーに問い合わせます。

下記の言語モデルでCoding Assistantアプリが利用可能です。

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- DeepSeek

### Jupyter Notebook :id=jupyter-notebook

![Jupyter Notebook app icon](../assets/icons/jupyter-notebook.png ':size=40')

AIがJupyter Notebookを作成して、ユーザーからのリクエストに応じてセルを追加し、セル内のコードを実行するアプリケーションです。コードの実行には、Dockerコンテナ内のPython環境が使用されます。作成されたNotebookは`Shared Folder`に保存されます。

?> Jupyterノートブックを実行するためのJupyterLabサーバーの起動と停止は、AIエージェントに自然言語で依頼する他に、Monadic Chatコンソールパネルのメニューからも行うことができます（`Start JupyterLab`, `Stop JupyterLab`）。
<br /><br />![Action menu](../assets/images/jupyter-start-stop.png ':size=190')

下記の言語モデルでJupyter Notebookアプリが利用可能です。

- OpenAI
- Anthropic Claude

