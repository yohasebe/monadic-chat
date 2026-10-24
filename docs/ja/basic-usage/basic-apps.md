# 基本アプリ

以下の基本アプリが使用可能です。いずれかの基本アプリを選択し、パラメータを変更したり、初期プロンプトを書き換えたりすることで、AIエージェントの挙動を調整できます。調整した設定は、外部のJSONファイルにエクスポート／インポートできます。

ほとんどの基本アプリは複数のAIプロバイダーに対応しています。プロバイダーごとのアプリ対応状況は下記の表を参照してください。

独自のアプリを作る方法については[アプリの開発](../advanced-topics/develop_apps.md)を参照してください。

## モデル対応状況 :id=app-availability

以下の表は、各アプリケーションがどのAIモデルプロバイダーで利用可能かを示しています。


| アプリ | OpenAI | Claude | Cohere | DeepSeek | Google Gemini | xAI Grok | Mistral | Ollama |
|-------|:------:|:------:|:------:|:--------:|:------:|:----:|:-------:|:------:|
| Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Chat Plus | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Voice Chat | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Live Conversation | ✅ | | | | ✅ | ✅ | | |
| Wikipedia | ✅ | | | | | | | |
| Math Tutor | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Second Opinion | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Research Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Language Practice | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Language Practice Plus | ✅ | ✅ | | | | | | |
| Translate | ✅ | | ✅ | ✅ | | | | |
| Voice Interpreter | ✅ | | ✅ | | | | | |
| Novel Writer | ✅ | | | ✅ | | | ✅ | |
| Image Generator | ✅ | | | | ✅ | ✅ | | |
| Video Generator | | | | | ✅ | ✅ | | |
| Music Generator | | | | | ✅ | | | |
| Mail Composer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mermaid Grapher | ✅ | ✅ | | | ✅ | ✅ | | |
| DrawIO Grapher | ✅ | ✅ | | | ✅ | ✅ | | |
| Syntax Tree | ✅ | ✅ | | | | | | |
| Concept Visualizer | ✅ | ✅ | | | | | | |
| Speech Draft Helper | ✅ | | | | | | | |
| Web Insight | ✅ | ✅ | | | ✅ | ✅ | | |
| Video Describer | ✅ | | | | ✅ | ✅ | | |
| Code Interpreter | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Coding Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Jupyter Notebook | ✅ | ✅ | | | ✅ | ✅ | | |
| Auto Forge | ✅ | ✅ | | | | ✅ | | |
| Music Lab | ✅ | ✅ | | | ✅ | ✅ | | |
| Music Analyst | | | | | ✅ | | | |
| Document Generator | | ✅ | | | | | | |
| Monadic Chat Help | ✅ | | | | | | | |

## アプリ別の Privacy Filter / Knowledge Base 対応 :id=privacy-kb-by-app

アプリは、Privacy Filter (PF) と Knowledge Base への保存 (KB) のどちらか一方に対応し、両方には対応しません。画像・動画・図・音楽・文書を作るアプリはどちらにも対応せず、その出力は共有フォルダ（`~/monadic/data`）に保存されます。

Privacy Filter を使った会話を残すには、上部のバーの Privacy の表示をクリックし、**Export this conversation** を使います（暗号化も、伏せた形での書き出しもできます）。Knowledge Base に保存したものを見るには、Knowledge Base パネルの **Browse** をクリックします。

| アプリ | Privacy Filter | Knowledge Base 保存 |
|-----|:--:|:--:|
| Chat | | ✅ |
| Chat Plus | ✅ | |
| Voice Chat | | ✅ |
| Live Conversation | | ✅ |
| Wikipedia | | ✅ |
| Math Tutor | | ✅ |
| Second Opinion | ✅ | |
| Research Assistant | | ✅ |
| Language Practice | | ✅ |
| Language Practice Plus | | ✅ |
| Translate | ✅ | |
| Voice Interpreter | | ✅ |
| Novel Writer | | ✅ |
| Image Generator | | |
| Video Generator | | |
| Music Generator | | |
| Mail Composer | ✅ | |
| Mermaid Grapher | | |
| DrawIO Grapher | | |
| Syntax Tree | | |
| Concept Visualizer | | |
| Speech Draft Helper | | ✅ |
| Web Insight | | ✅ |
| Video Describer | | ✅ |
| Code Interpreter | | ✅ |
| Coding Assistant | | ✅ |
| Jupyter Notebook | | ✅ |
| Auto Forge | | |
| Music Lab | | |
| Music Analyst | | |
| Document Generator | | |
| Monadic Chat Help | | ✅ |

両列とも空欄のアプリは、出力（画像・動画・図・文書など）をファイルとして保存するアプリです。メッセージの操作か共有フォルダから残してください。

## プロバイダー機能概要 :id=provider-capabilities

| プロバイダー | ビジョンサポート | ツール/関数呼び出し | Web検索 |
|----------|----------------|----------------------|---------|
| OpenAI | ✅ | ✅ | ✅ ネイティブ |
| Claude | ✅ | ✅ | ✅ ネイティブ |
| Gemini | ✅ | ✅ | ✅ ネイティブ |
| Mistral | ✅ | ✅ | ✅ Tavily |
| Cohere | ✅ | ✅ | ✅ Tavily |
| xAI Grok | ✅ | ✅ | ✅ ネイティブ |
| DeepSeek | ✅ | ✅ | ✅ Tavily |
| Ollama | モデル依存 | モデル依存 | ✅ Tavily |

## アプリカテゴリ

各アプリの詳細は個別ページにまとめられています。機能の説明や使い方のヒントは以下のリンク先を参照してください。

### チャット・アシスタントアプリ :id=chat-assistant-apps

標準チャットや音声チャットから、数学の学習支援、セカンドオピニオン、Web検索を使ったリサーチ、組み込みのドキュメントアシスタントまでを含む汎用会話アプリです。詳細は[チャット・アシスタントアプリ](../apps/chat-apps.md)を参照してください。

- Chat
- Chat Plus
- Voice Chat
- Live Conversation
- Wikipedia
- Math Tutor
- Second Opinion
- Research Assistant
- Monadic Chat Help

### 語学学習アプリ

音声での会話練習、テキストの翻訳、音声の通訳を行う語学学習向けアプリです。詳細は[語学学習アプリ](../apps/language-apps.md)を参照してください。

- Language Practice
- Language Practice Plus
- Translate
- Voice Interpreter

### 文章・ドキュメント作成アプリ

小説の共同執筆、メールやスピーチ原稿の作成、Officeドキュメント（Excel、PowerPoint、Word、PDF）の生成を行うアプリです。詳細は[文章・ドキュメント作成アプリ](../apps/writing-apps.md)を参照してください。

- Novel Writer
- Mail Composer
- Speech Draft Helper
- Document Generator

### Image Generator

テキストの説明から画像を生成し、自然な言葉の指示で画像を編集できます。詳細は[Image Generator](../apps/image-generator.md)を参照してください。

### Video Generator

テキストの説明や画像から動画を作れます。詳細は[Video Generator](../apps/video-generator.md)を参照してください。

### Music Generator

テキストの説明から音楽を生成します。ボーカルと歌詞を含むフル楽曲と、高速なインストゥルメンタルクリップの両方に対応しています。詳細は[Music Generator](../apps/music-generator.md)を参照してください。

### 図解・可視化アプリ

Mermaid.js、Draw.io、LaTeX/TikZ を使って自然言語の説明から図を作成するアプリです。ライブブラウザプレビューと視覚的な自己検証に対応しています。詳細は[図解・可視化アプリ](../apps/diagram-apps.md)を参照してください。

- Mermaid Grapher
- DrawIO Grapher
- Syntax Tree
- Concept Visualizer

### Web・メディア分析アプリ

ブラウザ操作によるWebページのキャプチャ・インタラクションや、動画の映像・音声内容の分析を行うアプリです。詳細は[Web・メディア分析アプリ](../apps/analysis-apps.md)を参照してください。

- Web Insight
- Video Describer

### Knowledge Base

保存した会話とインポートしたドキュメント（PDF、Office、Markdown、ソースコード）をプロジェクト全体で共有するライブラリです。各エントリは保存したアプリから検索でき、`Global` スコープに切り替えると、Knowledge Base を検索するほかのアプリからも（**Use Knowledge Base for retrieval (this session)** がオンのとき）検索できます。詳細は[Knowledge Base](../apps/knowledge-base.md)を参照してください。

### コーディング・ノートブックアプリ

サンドボックス化されたDocker環境でのコードの作成・実行、共有フォルダのファイル操作、Jupyter Notebookの構築を行うアプリです。詳細は[コーディング・ノートブックアプリ](../apps/coding-apps.md)を参照してください。

- Code Interpreter
- Coding Assistant
- Jupyter Notebook

### Music Lab と Music Analyst

演奏可能なサンプルとバッキングトラックで音楽理論を実践的に学び、録音された演奏を計測された特徴量と解釈的な批評の両面から評価できます。詳細は[Music Lab と Music Analyst](../apps/music-apps.md)を参照してください。

- Music Lab
- Music Analyst

### Auto Forge

説明をもとに、1 つのファイルでできた Web アプリケーションやコマンドラインのツールを作ります。詳細は [Auto Forge](../apps/auto_forge.md) を参照してください。
