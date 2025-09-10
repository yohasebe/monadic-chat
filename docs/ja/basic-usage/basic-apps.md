# 基本アプリ

以下の基本アプリが使用可能です。いずれかの基本アプリを選択し、パラメータを変更したり、初期プロンプトを書き換えたりすることで、AIエージェントの挙動を調整できます。調整した設定は、外部のJSONファイルにエクスポート／インポートできます。

ほとんどの基本アプリは複数のAIプロバイダーに対応しています。プロバイダーごとのアプリ対応状況は下記の表を参照してください。各プロバイダーで利用可能なモデルについては、[言語モデル](./language-models.md)を参照してください。

独自のアプリを作る方法については[アプリの開発](../advanced-topics/develop_apps.md)を参照してください。

## モデル対応状況 :id=app-availability

以下の表は、各アプリケーションがどのAIモデルプロバイダで利用可能かを示しています。


| アプリ | OpenAI | Claude | Cohere | DeepSeek | Google Gemini | xAI Grok | Mistral | Perplexity | Ollama |
|-------|:------:|:------:|:------:|:--------:|:------:|:----:|:-------:|:----------:|:------:|
| Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Chat Plus | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Voice Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Wikipedia | ✅ | | | | | | | | |
| Math Tutor | ✅ | | | | | | | | |
| Second Opinion | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Research Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Language Practice | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Language Practice Plus | ✅ | | | | | | | | |
| Translate | ✅ | | ✅ | | | | | | |
| Voice Interpreter | ✅ | | ✅ | | | | | | |
| Novel Writer | ✅ | | | | | | | | |
| Image Generator | ✅ | | | | ✅ | ✅ | | | |
| Video Generator | | | | | ✅ | | | | |
| Mail Composer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Mermaid Grapher | ✅ | | | | | | | | |
| DrawIO Grapher | ✅ | ✅ | | | | | | | |
| Syntax Tree | ✅ | ✅ | | | | | | | |
| Concept Visualizer | ✅ | ✅ | | | | | | | |
| Speech Draft Helper | ✅ | | | | | | | | |
| Visual Web Explorer | ✅ | ✅ | | | ✅ | ✅ | | | |
| Video Describer | ✅ | | | | | | | | |
| PDF Navigator | ✅ | | | | | | | | |
| Content Reader | ✅ | | | | | | | | |
| Code Interpreter | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | | |
| Coding Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Jupyter Notebook | ✅ | ✅ | | | ✅ | ✅ | | | |
| Monadic Chat Help | ✅ | | | | | | | | |

## アシスタント :id=assistant

### Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

標準的なチャットアプリケーションです。ユーザーが入力したテキストに対して、AIが適切な絵文字とともに応答します。Web検索機能は利用可能ですが、コストとプライバシーを考慮してデフォルトでは無効になっています。最新の情報が必要な場合は、アプリの設定で手動でWeb検索を有効にできます。

<!-- > 📸 **スクリーンショットが必要**: 絵文字を伴う会話を表示するChatアプリのインターフェース -->

下記の言語モデルでChatアプリが利用可能です。

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI
- Perplexity
- DeepSeek
- Cohere
- Ollama (ローカルモデル)

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
- Perplexity

### Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

基本的にChatと同じですが、言語モデルのカットオフ日時以降に発生したイベントに関する質問など、GPTが回答できない質問に対しては、Wikipediaを検索して回答します。問い合わせが英語以外の言語の場合、Wikipediaの検索は英語で行われ、結果は元の言語に翻訳されます。

### Math Tutor

![Math Tutor app icon](../assets/icons/math-tutor.png ':size=40')

AIチャットボットが [MathJax](https://www.mathjax.org/) の数式表記を用いて応答するアプリケーションです。数式の表示が必要なやりとりを行うのに適しています。

!> **注意:** LLMの数学的計算能力には制約があり、誤った結果が出力されることがあります。計算の正確性が求められる場合は、Code Interpreterアプリなどで実際に計算を行うことをお勧めします。

### Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

このアプリは2段階の相談プロセスを提供します。**ステップ1**: 質問をすると、AIから初期回答を受け取ります。**ステップ2**: 「セカンドオピニオンを求める」「Claudeはどう思う？」「この答えを検証して」などのフレーズで検証を依頼すると、別のAIプロバイダー（Claude、Gemini、Mistralなど）が初期回答をレビューしコメントします。これにより、回答の正確性を確保し、複雑なトピックについて多様な視点を得ることができます。

Second Opinionアプリは、サポートされているすべてのモデルで利用可能です：OpenAI、Claude、Gemini、Mistral、Cohere、Perplexity、xAI Grok、DeepSeek、Ollama。

### Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

アカデミックな研究や科学的研究をサポートするために設計されたアプリケーションで、強力なウェブ検索機能を持つインテリジェントな研究アシスタントとして機能します。オンラインソースから情報を取得・分析し、最新情報の検索、事実の検証、トピックの包括的な調査を支援します。研究アシスタントは、信頼性の高い詳細な洞察、要約、説明を提供し、あなたの探究を進めます。

下記の言語モデルでResearch Assistantアプリが利用可能です。

- OpenAI
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI（Tavily API必須）
- Cohere（Tavily API必須）
- DeepSeek（Tavily API必須）
- Perplexity

?> **ウェブ検索機能について**: 
> - **ネイティブ検索**：OpenAI（`gpt-4o-search-preview`モデル）、Anthropic Claude（`web_search_20250305`ツール）、xAI Grok（Live Search）、Google Gemini（ネイティブGoogle検索）、Perplexity（sonarモデルに組み込み）
> - **Tavily API必須**：Mistral AI、Cohere、DeepSeek。[Tavily](https://tavily.com/)から無料APIキーを取得できます（月1,000回の無料API呼び出し）

## 言語関連 :id=language-related

### Language Practice

![Language Practice app icon](../assets/icons/language-practice.png ':size=40')

アシスタントの発話から会話が始まる語学学習アプリケーションです。アシスタントの発話は音声合成で再生されます。ユーザーは、Enterキーを押して発話入力を開始し、もう一度Enterキーを押して発話入力を終了します。

<!-- > 📸 **スクリーンショットが必要**: 語学学習ガイダンスを伴う会話を表示するLanguage Practiceアプリ -->

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

TranslateアプリはOpenAIとCohereのモデルで利用可能です。

### Voice Interpreter

![Voice Interpreter app icon](../assets/icons/voice-chat.png ':size=40')

ユーザーが音声入力で与えた内容を別の言語に翻訳し、音声合成で発話します。まず、アシスタントは翻訳先の言語を尋ねます。次に、入力されたテキストを指定された言語に翻訳します。

Voice InterpreterアプリはOpenAIとCohereのモデルで利用可能です。

## コンテンツ生成 :id=content-generation

### Novel Writer

![Novel Writer app icon](../assets/icons/novel-writer.png ':size=40')

アシスタントと共同で小説を執筆するためのアプリケーションです。ユーザーのプロンプトに基づいてストーリーを展開し、一貫性と流れを維持します。AIエージェントは最初に、物語の舞台、登場人物、ジャンル、最終的な文章の量を尋ねます。その後、ユーザーが提供するプロンプトに基づいて、AIエージェントが物語を展開します。

### Image Generator

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

説明に基づいて画像を生成するアプリケーションです。

OpenAIバージョンは最新のgpt-image-1モデルを使用し、3つの主な操作をサポートしています：

1. **画像生成**：テキストの説明から新しい画像を作成
2. **画像編集**：テキストプロンプトとオプションのマスク画像を使用して既存の画像を修正
3. **画像バリエーション**：既存の画像の代替バージョンを生成

画像編集機能では、以下のことが可能です：
- 既存の画像をベースとして選択
- マスク画像を作成して編集領域を指定
  - アップロードした画像のマスクボタンをクリック
  - 画像上に描画して編集領域を選択
- 変更内容のテキスト指示を提供
- 以下を含む出力オプションのカスタマイズ：
  - 画像サイズと品質
  - 出力形式（PNG、JPEG、WebP）
  - 背景の透明度
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

- OpenAI（gpt-image-1を使用） - 画像生成、マスク描画による編集、バリエーション生成に対応
- Google Gemini（Imagen 3とGemini 2.5 Flash Image Previewを使用） - 画像生成とセマンティック編集（手動マスク不要の自然言語ベース編集）に対応
- xAI Grok - 画像生成に対応

### Video Generator

![Video Generator app icon](../assets/icons/video-generator.png ':size=40')

このアプリケーションは、Gemini APIを通じてGoogleのVeoモデルを使用して動画を生成します。テキストから動画への変換や、画像から動画への変換の両方が可能で、異なるアスペクト比や長さに対応しています。

対応モデル（Veo 3）:
- `veo-3.0-fast-generate-001` — 既定（高速・短時間、十分な画質）
- `veo-3.0-generate-001` — より高品質（所要時間は長め）

既定では高速モデルを使用します。より高品質を希望する場合は、プロンプトで「高品質モデルを使用して」などと指示すると切り替わります。

**主な機能：**
- **テキストから動画生成**: テキストの説明から動画を作成
- **画像から動画生成**: 既存の画像を第1フレームとして使用し、アニメーションを作成
- **アスペクト比オプション**: 横向き（16:9）、縦向き（9:16）の選択が可能
- **人物生成の制御**: 人物を含む動画の生成を許可または制限するオプション


**使用方法：**
1. テキストから動画: 作成したい動画の詳細な説明を提供
2. 画像から動画: 画像をアップロードし、どのようにアニメーションするか説明
3. 希望するアスペクト比や人物生成の設定を指定
4. AIがGoogleのVeoモデルを使用してリクエストを処理

?> **注意:** 動画生成は通常2～6分かかります。高速モデルを用いると所要時間を短縮できます。生成された動画は「共有フォルダ」に保存され、チャットインターフェースに表示されます。

**使用例：**
- 「山々に沈む夕日の動画を作成して」（テキストから動画）
- 「この画像を波が穏やかに動く動画に変換して」（アップロードした画像から動画）
- 「ダンシングロボットの縦向き動画を生成して」（9:16アスペクト比）

Video GeneratorはGoogle Geminiモデルでのみ利用可能です。

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

[mermaid.js](https://mermaid.js.org/) を活用してデータを視覚化するアプリケーションです。任意のデータや指示文を入力すると、エージェントが最適な図の種類を選択してMermaidコードを生成し、図を描画します。

**主な機能:**
- **自動的な図の種類選択**: AIがデータに最適な図の種類を選択（フローチャート、シーケンス図、クラス図、状態図、ER図、ガントチャート、円グラフ、サンキー図、マインドマップなど）
- **強化された検証システム**: Seleniumを使用して実際のMermaid.jsエンジンで図を検証し、正確な構文チェックを実現
- **エラー自動修正**: 構文エラーが発生した場合、AIが自動的に分析して修正
- **プレビュー生成**: PNG形式のプレビュー画像を共有フォルダに保存

**使用のヒント:**
- 視覚化したい内容を説明するだけで、AIが適切な図を作成します
- サンキー図では、矢印記法ではなくCSV形式（source,target,value）を使用することに注意
- すべてのプレビュー画像は共有フォルダに `mermaid_preview_[タイムスタンプ].png` として保存されます


### DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Draw.io ダイアグラムを作成するためのアプリケーションです。必要な図の仕様を説明すると、AIエージェントがDraw.io XMLファイルを生成し、共有フォルダに保存します。生成されたファイルはDraw.ioにインポートして編集することができます。フローチャート、UMLダイアグラム、ER図、ネットワーク図、組織図、マインドマップ、BPMNダイアグラム、ベン図、ワイヤフレームなど、様々な種類の図を作成できます。


下記の言語モデルでDrawIO Grapherアプリが利用可能です。

- OpenAI
- Anthropic Claude

### Syntax Tree

![Syntax Tree app icon](../assets/icons/syntax-tree.png ':size=40')

言語学的な構文木（統語樹）を生成するアプリケーションです。複数の言語の文を分析し、その文法構造を視覚的な樹形図として表示します。LaTeXとtikz-qtreeを使用して生成されます。主な機能：

- 英語、日本語、中国語を含む多言語対応
- 二分枝分析（各ノードが最大2つの子ノードを持つ）
- ベクターグラフィックエディタで編集可能なSVG出力
- 日本語の包括的な助詞分析（すべての助詞を含む）
- 統語理論に基づいた専門的な言語学記法

生成された構文木は透明背景のSVG画像として表示され、Web表示用にCSSでスタイリングされます。


下記の言語モデルでSyntax Treeアプリが利用可能です。

- OpenAI
- Anthropic Claude

### Concept Visualizer :id=concept-visualizer

![Concept Visualizer app icon](../assets/icons/diagram-draft.png ':size=40')

LaTeX/TikZを使用して、様々な概念や関係性を図式化するアプリケーションです。自然言語での説明に基づいて、マインドマップ、フローチャート、組織図、ネットワーク図など、多様な視覚的表現を作成できます。主な機能：

- **幅広い図式タイプ**: マインドマップ、フローチャート、組織図、ネットワーク図、タイムライン、ベン図、3D視覚化など
- **自然言語入力**: 視覚化したい内容を普通の言葉で説明するだけ
- **多分野対応**: ビジネス図（SWOT分析、ビジネスモデル）、教育図（概念マップ、学習パス）、科学図（分子構造、食物網、3Dプロット）、技術図（システムアーキテクチャ、UML）
- **多言語サポート**: 中国語、日本語、韓国語を含む様々な言語のテキストに対応
- **プロフェッショナルな出力**: プレゼンテーションや出版物に適した高品質なSVG図を生成
- **カスタマイズ可能**: 各図式タイプに適した色、レイアウト、視覚要素
- **3D機能**: tikz-3dplotを使用した3D散布図、曲面、その他の三次元視覚化をサポート

生成された図は編集可能なSVG画像として表示され、ベクターグラフィックエディタでさらに修正することができます。


**技術的な注意事項:**
- LaTeX/TikZを使用した図形生成で、以下を含む包括的なパッケージサポート：
  - 基本的な図形作成のためのコアLaTeXパッケージ
  - tikz-3dplotによる3D視覚化のための`texlive-science`
  - 多言語テキストレンダリングのためのCJK言語サポート
  - 高品質なSVG出力のための`dvisvgm`
- 生成されたSVGファイルは共有フォルダに保存され、`/data/`エンドポイント経由で表示
- 図式タイプに基づいて適切なTikZライブラリを自動的に検出・読み込み

下記の言語モデルでConcept Visualizerアプリが利用可能です。

- OpenAI
- Anthropic Claude

### Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

このアプリでは、AIエージェントにスピーチのドラフト作成を依頼することができます。ドラフトを一から作成することもできますし、既存のドラフトを、テキスト文字列、Wordファイル、PDFファイルの形で提出することもできます。AIエージェントはそれらを分析し、修正版を返します。また、必要であれば、スピーチをより魅力的で効果的なものにするための改善案やヒントを提供します。スピーチの音声ファイルを提供することもできます（OpenAIとElevenLabsはMP3形式、GeminiはWAV形式）。


## コンテンツ分析 :id=content-analysis

### Visual Web Explorer :id=visual-web-explorer

このアプリケーションは、Webページをスクリーンショットとして撮影したり、テキストコンテンツをMarkdown形式で抽出したりします。ドキュメント作成、Webコンテンツのアーカイブ、ページコンテンツの分析に最適です。

**主な機能:**
- **スクリーンショットモード**: ページ全体を自動スクロールしながら複数のビューポートサイズの画像として撮影
- **テキスト抽出モード**: WebコンテンツをクリーンなMarkdown形式に変換
- **プロバイダー別画像認識**: HTMLパースが失敗した場合、各プロバイダーのネイティブビジョンAPIを使用してテキスト抽出
- **カスタマイズ可能なビューポート**: デスクトップ（1920×1080）、タブレット（1024×768）、モバイル（375×812）、印刷（794×1123）のプリセット
- **オーバーラップ制御**: シームレスな読み取りのためのスクリーンショット間のオーバーラップを設定可能
- **自動命名**: ファイルはドメイン名とタイムスタンプで命名

**使用例:**
- `"https://github.com のスクリーンショットを撮って"` - 複数のスクリーンショットを撮影
- `"https://example.com からテキストを抽出して"` - Markdownに変換
- `"https://example.com から画像認識でテキストを抽出して"` - 必要時にビジョンAPIを使用
- `"https://example.com のモバイル版スクリーンショットを撮って"` - モバイルビューポートプリセットを使用


**技術的な詳細:**
- ページレンダリングにSelenium WebDriverを使用
- `webpage_fetcher.py`がHTMLからMarkdownへの変換を処理
- テキスト抽出が失敗した場合、プロバイダー固有の画像認識APIにフォールバック
- 各プロバイダー（OpenAI、Claude、Gemini、Grok）がネイティブ画像フォーマットを使用

Visual Web Explorerアプリは以下のモデルで利用可能です:
- OpenAI
- Anthropic Claude
- Google Gemini
- xAI Grok

### Video Describer

![Video Describer app icon](../assets/icons/video-describer.png ':size=40')

動画コンテンツを分析し、その内容を説明するアプリケーションです。AIが動画コンテンツを分析し中で何が起こっているのかを詳細に説明します。

アプリ内部で動画からフレームを抽出し、それらをbase64形式のPNG画像に変換します。さらに、ビデオから音声データを抽出し、MP3ファイルとして保存します。これらに基づいてAIが動画ファイルに含まれる視覚および音声情報の全体的な説明を行います。

このアプリを使用するには、ユーザーは動画ファイルを`Shared Folder`に格納して、ファイル名を伝える必要があります。また、フレーム抽出のための秒間フレーム数（fps）を指定する必要があります。総フレーム数が50を超える場合はビデオ全体から50フレームが選択・抽出されます。


### PDF Navigator

![PDF Navigator app icon](../assets/icons/pdf-navigator.png ':size=40')

PDFファイルを読み込み、その内容に基づいてユーザーの質問に答えるアプリケーションです。`Upload PDF` ボタンをクリックしてファイルを指定してください。ファイルの内容はmax_tokensの長さのセグメントに分割され、セグメントごとにテキストエンベディングが計算されます。ユーザーからの入力を受け取ると、入力文のテキストエンベディング値に最も近いテキストセグメントがユーザーの入力値とともにGPTに渡され、その内容に基づいて回答が生成されます。

?> PDF ファイルからのテキスト抽出には、[PyMuPDF](https://pymupdf.readthedocs.io/en/latest/) ライブラリが使用されます。抽出したテキストとエンベディングデータは [PGVector](https://github.com/pgvector/pgvector) データベース（データベース名：`monadic_user_docs`）に確実に保存され、アプリケーションは適切にベクトルデータベースに接続してPDFコンテンツの検索と取得を行います。ベクトルデータベース関連の実装に関する詳細は、[ベクトルデータベース](../docker-integration/vector-database.md)のドキュメントを参照してください。

**設定オプション：**

PDF Navigatorの動作は`~/monadic/config/env`の環境変数でカスタマイズできます：

- `PDF_RAG_TOKENS`: チャンクあたりのトークン数（デフォルト：4000）
  - PDFテキストをエンベディング用のチャンクに分割する方法を制御
  - 大きい値はより多くのコンテキストを提供しますが、検索精度が低下する可能性があります
  - 推奨範囲：2000-6000トークン

- `PDF_RAG_OVERLAP_LINES`: チャンク間でオーバーラップする行数（デフォルト：4）
  - 隣接するチャンク間の連続性を提供
  - チャンク境界でのコンテキスト損失を防ぎます
  - 推奨範囲：2-10行

設定例：
```
PDF_RAG_TOKENS=5000
PDF_RAG_OVERLAP_LINES=6
```


![PDF button](../assets/images/app-pdf.png ':size=700')


![Import PDF](../assets/images/import-pdf.png ':size=400')

![PDF DB Panel](../assets/images/monadic-chat-pdf-db.png ':size=400')

### Content Reader

![Content Reader app icon](../assets/icons/content-reader.png ':size=40')

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

?> **重要な注意事項：**
> - コード実行に失敗した場合の無限ループを防ぐため、自動エラーハンドリングが実装されています
> - コード実行で繰り返しエラーが発生する場合、アプリは自動的に再試行を停止し、エラーメッセージを表示します
> - 日本語テキストを含むmatplotlibプロットでは、Pythonコンテナに日本語フォントサポート（Noto Sans CJK JP）がmatplotlibrcを通じて設定されています

<!-- > 📸 **スクリーンショットが必要**: コード実行と出力および生成されたプロットを表示するCode Interpreter -->

下記の言語モデルでCode Interpreterアプリが利用可能です。

- OpenAI
- Anthropic Claude（コード実行には`run_code`ツールを使用）
- Cohere
- DeepSeek
- Google Gemini
- xAI Grok

?> **注意:** Perplexityはツールコーリング（関数呼び出し）をサポートしていないため、Code Interpreterアプリは利用できません。Perplexityではコードの提案のみが可能で、実行はできません。

### Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

これはコンピュータプログラムコードを書くためのアプリケーションです。プロフェッショナルなソフトウェアエンジニアとして設定が与えられたAIと対話することができます。ユーザーからのプロンプトを通じて様々なな質問に答え、コードを書き、適切な提案を行い、役立つアドバイスを提供します。

?> **注意:** Code InterpreterアプリはDocker上のPython環境でコードを実行することができますが、Coding Assistantアプリはコードの生成に特化しており、コードの実行は行いません。長いコードはいくつかの断片に分割し、分割点ごとに続きを表示するかをユーザーに問い合わせます。


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

!> **セキュリティに関する注意:** サーバーモードでは、セキュリティ上の理由からJupyter Notebook機能はデフォルトで無効になっています。有効にするには、設定ファイル（`~/monadic/config/env`）で`ALLOW_JUPYTER_IN_SERVER_MODE=true`を明示的に設定する必要があります。マルチユーザー環境でJupyterを実行することのセキュリティ上の影響を理解している場合のみ有効にしてください。

下記のプロバイダーでJupyter Notebookアプリが利用可能です。

- OpenAI
- Anthropic Claude
- Google Gemini
- xAI Grok

?> **プロバイダー別の注意事項:**
> - **Gemini**: ノートブックの作成とセルの追加を確実に行うため、`create_and_populate_jupyter_notebook`という統合関数を使用しています
> - すべてのプロバイダーはノートブックの作成、セルの追加、Jupyter環境内でのPythonコード実行をサポートしています

### Monadic Chat Help

![Help app icon](../assets/icons/help.png ':size=40')

Monadic Chat用のAI駆動ヘルプアシスタントです。プロジェクトのドキュメントに基づいて、機能、使用方法、トラブルシューティングについての質問に任意の言語で文脈に応じた支援を提供します。

ヘルプシステムは、英語のドキュメントから作成された事前構築されたナレッジベースを使用します。質問をすると、関連情報を検索し、公式ドキュメントに基づいて正確な回答を提供します。ヘルプシステムのアーキテクチャの詳細については、[ヘルプシステム](../advanced-topics/help-system.md)を参照してください。
