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
| Mail Composer | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mermaid Grapher | ✅ | ✅ | | | ✅ | ✅ | | |
| DrawIO Grapher | ✅ | ✅ | | | ✅ | ✅ | | |
| Syntax Tree | ✅ | ✅ | | | | | | |
| Concept Visualizer | ✅ | ✅ | | | | | | |
| Speech Draft Helper | ✅ | | | | | | | |
| Web Insight | ✅ | ✅ | | | ✅ | ✅ | | |
| Video Describer | ✅ | | | | | | | |
| Knowledge Base | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Code Interpreter | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Coding Assistant | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Jupyter Notebook | ✅ | ✅ | | | ✅ | ✅ | | |
| Auto Forge | ✅ | ✅ | | | | ✅ | | |
| Music Lab | ✅ | ✅ | | | ✅ | ✅ | | |
| Music Analyst | | | | | ✅ | | | |
| Document Generator | | ✅ | | | | | | |
| Monadic Chat Help | ✅ | | | | | | | |

## アプリ別の Privacy Filter / Knowledge Base 対応 :id=privacy-kb-by-app

Privacy Filter (PF) と Knowledge Base への保存 (KB) はアプリ単位で**相互排他**です。意図的に PII を扱うアプリは「PF を有効にした一過性の会話」として位置づけ、会話そのものに長期的な参照価値があるアプリは「PF オフで KB に保存できる」スコープに配置されます。第三のグループ (画像 / 動画 / 図 / 文書ジェネレーターなどの artifact 中心アプリ) はどちらの機能も持ちません — artifact 自体は `~/monadic/data/` に保存され、周囲の会話はイテレーションのログに過ぎないため、KB に入れても検索ノイズになるだけです。

PF で保護された会話を残したい場合は **Privacy Export** (暗号化、必要に応じて placeholder のみの masked) を使ってください。KB エントリの閲覧 / 共有は右サイドバーの **Browse** モーダルから行います。

| アプリ | Privacy Filter | Knowledge Base 保存 |
|-----|:--:|:--:|
| Chat | | ✅ |
| Chat Plus | ✅ | |
| Voice Chat | | ✅ |
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
| Mail Composer | ✅ | |
| Mermaid Grapher | | |
| DrawIO Grapher | | |
| Syntax Tree | | |
| Concept Visualizer | | |
| Speech Draft Helper | | ✅ |
| Web Insight | | ✅ |
| Video Describer | | ✅ |
| Knowledge Base | | ✅ |
| Code Interpreter | | ✅ |
| Coding Assistant | | ✅ |
| Jupyter Notebook | | ✅ |
| Auto Forge | | |
| Music Lab | | |
| Music Analyst | | |
| Document Generator | | |
| Monadic Chat Help | | ✅ |

両列とも空欄になっているアプリは artifact 中心の生成系で、生成された出力 (画像・動画・図・文書など) 自体に価値があり会話本文ではありません。artifact を保管するにはカードの **Copy** / **Download** ボタンや共有フォルダを使ってください。周囲のチャットには retrieval 価値がないため KB 保存はあえて提供していません。

## プロバイダー機能概要

| プロバイダー | ビジョンサポート | ツール/関数呼び出し | Web検索 |
|----------|----------------|----------------------|---------|
| OpenAI | ✅ | ✅ | ✅ ネイティブ |
| Claude | ✅ | ✅ | ✅ ネイティブ |
| Gemini | ✅ | ✅ | ✅ ネイティブ |
| Mistral | ✅ | ✅ | ✅ Tavily |
| Cohere | ✅ | ✅ | ✅ Tavily |
| xAI Grok | ✅ | ✅ | ✅ ネイティブ |
| DeepSeek | ❌ | ✅ | ✅ Tavily |
| Ollama | モデル依存 | モデル依存 | ✅ Tavily |

## アシスタント :id=assistant

### Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

標準的なチャットアプリケーションです。ユーザーが入力したテキストに対して、AIが適切な絵文字とともに応答します。Web検索機能は以下の方法で利用できます：
- **ネイティブ検索**: OpenAI、Claude、Gemini、Grokは組み込みのWeb検索機能を使用（対応アプリでデフォルト有効）
- **Tavily検索**: Mistral、Cohere、DeepSeek、Ollamaは設定ファイルに`TAVILY_API_KEY`を追加することでTavily APIを使用

また、メッセージ入力エリアの`URLから読込`機能により、プロバイダーに関係なく、Seleniumベースのスクレイピングで任意のURLのコンテンツを抽出できます。

本アプリの対応プロバイダーはページ冒頭の表を参照してください。


### Chat Plus

![Chat app icon](../assets/icons/chat-plus.png ':size=40')

Chatアプリの拡張版で、"monadic" な振る舞いを示します。AIの回答の背後で下記の情報を保持し、随時更新します。

- reasoning: 回答の作成における動機づけと根拠など
- topics: ここまでの会話で取り上げられたトピック
- people: 会話に関連する人物
- notes: 会話で取り上げられた重要なポイント


### Voice Chat :id=voice-chat

![Voice Chat app icon](../assets/icons/voice-chat.png ':size=40')

選択したプロバイダーの音声認識APIとブラウザの音声合成APIを組み合わせ、音声でチャットを行えるアプリケーションです。初期プロンプトは基本的にChatアプリと同じです。

<!-- SCREENSHOT: 音声入力中の画面 - Speech Inputボタンの代わりにStopボタンが表示され、音声波形が動いている様子 -->

音声入力中は波形が表示されます。プロバイダー/モデルによっては、音声入力が終了すると、認識の「確からしさ」を示すp-value（0〜1の値）が表示されます。

<!-- SCREENSHOT: 音声入力後のp-value表示 - テキストエリア上部に「p-value: 0.95」などの信頼度スコアが表示されている様子 -->

Voice Chatの対応プロバイダーは冒頭の表を参照してください。チャットプロバイダーとTTSプロバイダーの組み合わせは自由です（例: Claudeで会話しながらxAI Grokで音声出力）。音声入出力の設定については[音声設定パネル](./web-interface.md#speech-settings-panel)を参照してください。

**Expressive Speech**: Auto Speech をオンにし、対応する TTS プロバイダーを選択すると、Text-to-Speech Provider ドロップダウンの下に✨ **Expressive Speech** バッジが表示されます。プロバイダーに応じて 3 種類の仕組みが自動的に選択されます。

- **インラインマーカー方式** (xAI Grok / ElevenLabs v3): アシスタントが応答テキスト内に短いマーカー（短い間・笑い・ささやく一言など）を織り交ぜ、TTS エンジンがそれをステージ指示として解釈します。マーカーはチャット履歴には一切現れず、音声の抑揚としてのみ反映されます。
- **インストラクションモード** (OpenAI `gpt-4o-mini-tts`): アシスタントが応答本文とは別に、声質・テンポ・感情・発音・間取りなどの発話方針を送出します。OpenAI TTS はその指示を「読み上げず」に参考にして本文を発話します。指示文はチャット履歴にも画面にも現れず、内容に合った表情豊かな音声のみが再生されます。
- **ハイブリッド方式** (Gemini TTS): Gemini は上記 2 つを同時にサポートします。アシスタントはインラインマーカー、発話方針、またはその両方を自由に組み合わせて送出でき、Google のエンジンがそれぞれを解釈します。応答本文以外はすべてチャット履歴から剥がされます。

バッジにマウスオーバーすると、現在有効な仕組みの説明がツールチップで表示されます。Auto Speech をオフにするか、Expressive Speech 非対応の TTS プロバイダーへ切り替えると、この機能は自動的に無効になります。


### Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

基本的にChatと同じですが、言語モデルのカットオフ日時以降に発生したイベントに関する質問など、AIが回答できない質問に対しては、Wikipediaを検索して回答します。問い合わせが英語以外の言語の場合、Wikipediaの検索は英語で行われ、結果は元の言語に翻訳されます。


### Math Tutor

![Math Tutor app icon](../assets/icons/math-tutor.png ':size=40')

AIチャットボットが [KaTeX](https://katex.org/) の数式表記を用いて応答するアプリケーションです。数式の表示が必要なやりとりを行うのに適しています。

!> **注意:** LLMの数学的計算能力には制約があり、誤った結果が出力されることがあります。計算の正確性が求められる場合は、Code Interpreterアプリなどで実際に計算を行うことをお勧めします。


### Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

このアプリは2段階の相談プロセスを提供します。**ステップ1**: 質問をすると、AIから初期回答を受け取ります。**ステップ2**: 「セカンドオピニオンを求める」「別の視点で確認して」などのフレーズで検証を依頼すると、別のAIプロバイダーが初期回答をレビューしコメントします。これにより、回答の正確性を確保し、複雑なトピックについて多様な視点を得ることができます。

Second Opinionアプリの対応状況は冒頭の表を参照してください。


### Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

アカデミックな研究や科学的研究をサポートするために設計されたアプリケーションで、強力なウェブ検索機能を持つインテリジェントな研究アシスタントとして機能します。オンラインソースから情報を取得・分析し、最新情報の検索、事実の検証、トピックの包括的な調査を支援します。研究アシスタントは、信頼性の高い詳細な洞察、要約、説明を提供し、あなたの探究を進めます。

Research Assistantの対応プロバイダーは冒頭の表を参照してください。Web検索機能：
- **ネイティブ検索**: OpenAI、Claude、Gemini、Grok（常に利用可能）
- **Tavily検索**: Mistral、Cohere、DeepSeek、Ollama（`TAVILY_API_KEY`が必要）
- **URLコンテンツ抽出**: 任意のURLからコンテンツを取得するSeleniumベースのスクレイピング（全プロバイダーで利用可能）

> **注意**: GeminiのResearch Assistantは、ネイティブGoogle検索グラウンディングの代わりに内部ウェブ検索エージェント（`gemini_web_search`）を使用します。これにより、GeminiのAPI制限を回避し、ウェブ検索とファイル操作・プログレストラッキングを同時に利用できます。

詳細については、上記のChatアプリの説明または[URLからのテキスト読み込み](./message-input.md#reading-text-from-urls)を参照してください。


## 言語関連 :id=language-related

### Language Practice

![Language Practice app icon](../assets/icons/language-practice.png ':size=40')

アシスタントの発話から会話が始まる語学学習アプリケーションです。アシスタントの発話は音声合成で再生されます。ユーザーは、Enterキーを押して発話入力を開始し、もう一度Enterキーを押して発話入力を終了します。

Language Practiceの対応プロバイダーは冒頭の表を参照してください。音声合成の設定については[音声設定パネル](./web-interface.md#speech-settings-panel)を参照してください。


### Language Practice Plus

![Language Practice Plus app icon](../assets/icons/language-practice-plus.png ':size=40')

アシスタントの発話から会話が始まる語学学習アプリケーションです。アシスタントの発話は音声合成で再生されます。ユーザーは、Enterキーを押して発話入力を開始し、もう一度Enterキーを押して発話入力を終了します。アシスタントは、通常の応答に加えて、言語的なアドバイスを含めます。言語的なアドバイスは、音声ではなくテキストとしてのみ提示されます。


### Translate

![Translate app icon](../assets/icons/translate.png ':size=40')

ユーザーの入力テキストを別の言語に翻訳します。まず、AIアシスタントが翻訳先の言語を尋ねます。次に、ユーザーの入力テキストを指定された言語に翻訳します。特定の表現に関して、それらをどのように訳すかを指定したい場合は、入力テキストの該当箇所に括弧を付け、括弧内に翻訳表現を指定してください。

Translateアプリの対応プロバイダーは冒頭の表を参照してください。


### Voice Interpreter

![Voice Interpreter app icon](../assets/icons/voice-chat.png ':size=40')

ユーザーが音声入力で与えた内容を別の言語に翻訳し、音声合成で発話します。まず、アシスタントは翻訳先の言語を尋ねます。次に、入力されたテキストを指定された言語に翻訳します。

Voice Interpreterの対応プロバイダーは冒頭の表を参照してください。音声入出力の設定については[音声設定パネル](./web-interface.md#speech-settings-panel)を参照してください。


## コンテンツ生成 :id=content-generation

### Novel Writer

![Novel Writer app icon](../assets/icons/novel-writer.png ':size=40')

アシスタントと共同で小説を執筆するためのアプリケーションです。ユーザーのプロンプトに基づいてストーリーを展開し、一貫性と流れを維持します。AIエージェントは最初に、物語の舞台、登場人物、ジャンル、最終的な文章の量を尋ねます。その後、ユーザーが提供するプロンプトに基づいて、AIエージェントが物語を展開します。


### Image Generator

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

説明に基づいて画像を生成するアプリケーションです。Image GeneratorはOpenAI、Google Gemini、xAI（Grok）で利用可能です。

対応プロバイダーが高度な画像ワークフローを提供している場合、以下の3つの主な操作を利用できます：

1. **画像生成**：テキストの説明から新しい画像を作成
2. **画像編集**：テキストプロンプトを使用して既存の画像を修正
3. **画像バリエーション**：既存の画像の代替バージョンを生成

対応モデルでは、画像編集機能で以下のことが可能です：
- 既存の画像をベースとして選択
- テキストで変更内容を指示（プロンプトベース編集）
- 以下を含む出力オプションのカスタマイズ：
  - 画像サイズと品質
  - 出力形式（PNG、JPEG、WebP）
  - 背景の透明度
  - 圧縮レベル


### 画像編集

既存の画像を編集するには、変更内容を自然言語で指示するだけです。モデルが全体の構図を維持しながら、プロンプトに基づいて画像を修正します。画像編集はOpenAI、Google Gemini、xAI（Grok）で対応しています。

例えば、画像を生成した後に以下のように指示できます：
- 「空を夕焼けのオレンジに変えて」
- 「窓に猫を座らせて」
- 「看板の文字を "Hello World" に変えて」

モデルが指示を解釈し、画像全体に対してコンテキストに応じた変更を適用します。画像をアップロードして編集指示を出すことも可能です。

生成されたすべての画像は`Shared Folder`に保存されると共に、チャット上でも表示されます。

### Video Generator

![Video Generator app icon](../assets/icons/video-generator.png ':size=40')

このアプリケーションは、最先端のAIモデルを使用して動画を生成します。テキストから動画への変換や、画像から動画への変換の両方が可能で、異なるアスペクト比や長さに対応しています。

プロバイダーによっては、高速モデルと高品質モデルを提供している場合があります。高品質を希望する場合は、プロンプトで「高品質」「本番用」などのキーワードを使用してください。

**主な機能：**
- **テキストから動画生成**: テキストの説明から動画を作成
- **画像から動画生成**: 既存の画像を第1フレームとして使用し、アニメーションを作成
- **Remix**: 生成済み動画を新しいプロンプトで修正（一部プロバイダーのみ対応）
- **複数のアスペクト比**: 横向き・縦向きフォーマットの選択が可能

**使用方法：**
1. テキストから動画: 作成したい動画の詳細な説明を提供
   - ショットタイプ、被写体、動作、設定、照明、カメラの動きを含める
2. 画像から動画: 共有フォルダに画像をアップロードし、どのようにアニメーションするか説明
3. Remix（一部プロバイダーのみ対応）: 動画生成後、修正を依頼可能
4. 必要に応じて品質設定をプロンプトで指定

?> **注意:** 生成された動画は「共有フォルダ」に保存され、チャットインターフェースに表示されます。

**使用例：**
- 「山々に沈む夕日の動画を作成して」 → テキストから動画生成
- 「高品質なマーケティング動画を作成」 → 高品質モデルでテキストから動画生成
- 「この画像を波が穏やかに動く動画に変換して」 → 画像から動画生成
- 「動画をもっとカラフルにして」（生成後） → Remix機能で修正（一部プロバイダーのみ対応）

Video Generatorの対応プロバイダーは冒頭の表を参照してください。


### Mail Composer

![Mail Composer app icon](../assets/icons/mail-composer.png ':size=40')

アシスタントと共同でメールの草稿を作成するためのアプリケーションです。ユーザーの要望や指定に応じて、アシスタントがメールの草稿を作成します。


Mail Composerの対応プロバイダーは冒頭の表を参照してください。


### Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

[mermaid.js](https://mermaid.js.org/) を活用してデータを視覚化するアプリケーションです。任意のデータや指示文を入力すると、エージェントが最適な図の種類を選択してMermaidコードを生成し、図を描画します。

**主な機能:**
- **ライブブラウザプレビュー**: noVNC（`http://localhost:7900`）経由で実ブラウザに図を描画し、変更をリアルタイムに確認可能
- **自動的な図の種類選択**: AIがデータに最適な図の種類を選択（フローチャート、シーケンス図、クラス図、状態図、ER図、ガントチャート、円グラフ、サンキー図、マインドマップなど）
- **強化された検証システム**: Seleniumを使用して実際のMermaid.jsエンジンで図を検証し、正確な構文チェックを実現
- **視覚的な自己検証**: AIが描画されたダイアグラムのスクリーンショットを撮影し、レイアウトの問題やレンダリングエラーがないか視覚的に確認した上でユーザーに回答します
- **エラー分析**: 構文エラーが発生した場合、エラーパターンを分析して修正提案を提供
- **プレビュー生成**: PNG形式のプレビュー画像を共有フォルダに保存

**使用のヒント:**
- 視覚化したい内容を説明するだけで、AIが適切な図を作成します
- `http://localhost:7900` を別ブラウザで開く（またはElectronのnoVNCメニューを使用する）と、図がリアルタイムで描画される様子を確認できます
- すべてのプレビュー画像は共有フォルダに `mermaid_preview_[タイムスタンプ].png` として保存されます

Mermaid Grapherの対応プロバイダーは冒頭の表を参照してください。


### DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Draw.io ダイアグラムを作成するためのアプリケーションです。必要な図の仕様を説明すると、AIエージェントがDraw.io XMLを生成・検証し、noVNC経由でブラウザにライブプレビューを表示します。

**主な機能:**
- **ライブブラウザプレビュー**: noVNC（`http://localhost:7900`）経由で実ブラウザに図を描画し、変更をリアルタイムに確認可能
- **自動XML検証・修復**: 生成されたDraw.io XMLの構造を検証し、一般的な構造上の問題を自動修復
- **幅広い図の種類**: フローチャート、UMLダイアグラム（クラス図、シーケンス図、アクティビティ図）、ER図、ネットワーク図、組織図、マインドマップ、BPMNダイアグラム、ベン図、ワイヤフレームなど
- **視覚的な自己検証**: AIが描画されたダイアグラムのスクリーンショットを撮影し、レイアウトの問題やレンダリングエラーがないか視覚的に確認した上でユーザーに回答します
- **プレビュー生成**: PNG形式のプレビュー画像を共有フォルダに保存
- **ダウンロード可能な.drawioファイル**: 生成された `.drawio` ファイルは共有フォルダに保存され、Draw.ioにインポートして編集可能

**使用のヒント:**
- 必要な図を説明するだけで、AIが適切なDraw.io XMLを作成します
- `http://localhost:7900` を別ブラウザで開く（またはElectronのnoVNCメニューを使用する）と、図がリアルタイムで描画される様子を確認できます
- すべてのプレビュー画像は共有フォルダに `drawio_preview_[タイムスタンプ].png` として保存されます

DrawIO Grapherの対応プロバイダーは冒頭の表を参照してください。


### Syntax Tree

![Syntax Tree app icon](../assets/icons/syntax-tree.png ':size=40')

言語学的な樹形図（統語樹）を生成するアプリケーションです。複数の言語の文を分析し、その文法構造を視覚的な樹形図として表示します。LaTeXとtikz-qtreeを使用して生成されます。主な機能：

- 英語、日本語、中国語を含む多言語対応
- ベクターグラフィックエディタで編集可能なSVG出力
- 統語理論に基づいた専門的な言語学記法

生成された樹形図は透明背景のSVG画像として表示されます。


Syntax Treeの対応プロバイダーは冒頭の表を参照してください。


### Concept Visualizer :id=concept-visualizer

![Concept Visualizer app icon](../assets/icons/diagram-draft.png ':size=40')

LaTeX/TikZを使用して、様々な概念や関係性を図式化するアプリケーションです。自然言語での説明に基づいて、マインドマップ、フローチャート、組織図、ネットワーク図など、多様な視覚的表現を作成できます。主な機能：

- **幅広い図式タイプ**: マインドマップ、フローチャート、組織図、ネットワーク図、タイムライン、ベン図、3D視覚化など
- **自然言語入力**: 視覚化したい内容を普通の言葉で説明するだけ
- **多分野対応**: ビジネス図（SWOT分析、ビジネスモデル）、教育図（概念マップ、学習パス）、科学図（分子構造、食物網、3Dプロット）、技術図（システムアーキテクチャ、UML）
- **多言語サポート**: 中国語、日本語、韓国語を含む様々な言語のテキストに対応
- **プロフェッショナルな出力**: プレゼンテーションや出版物に適した高品質なSVG図を生成
- **カスタマイズ可能**: 各図式タイプに適した色、レイアウト、視覚要素
- **3D機能**: 3D散布図、曲面、その他の三次元視覚化をサポート

生成された図は編集可能なSVG画像として共有フォルダに保存され、ベクターグラフィックエディタでさらに修正することができます。

Concept Visualizerの対応プロバイダーは冒頭の表を参照してください。


### Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

このアプリでは、AIエージェントにスピーチのドラフト作成を依頼することができます。ドラフトを一から作成することもできますし、既存のドラフトをテキスト、Word、PDF形式で提出することも可能です。AIエージェントは内容を分析し、修正版や改善案を提案します。必要に応じて、設定したテキスト読み上げプロバイダーがサポートする形式（例：MP3やWAV）で音声ファイルを生成できます。


## コンテンツ分析 :id=content-analysis

### Web Insight :id=web-insight

スクリーンショット付きでWebコンテンツを閲覧・キャプチャするアプリケーションです。URLを指定するとAIがページをビューポートサイズのスクリーンショットとして撮影します。インタラクション（クリック、フォーム入力、ナビゲーション）が必要な場合は、AIがヘッドレスブラウザセッションを開き、各アクション後にスクリーンショットを返します。

**主な機能:**
- **スクリーンショット撮影**: ページ全体を自動スクロールしながら複数のビューポートサイズの画像として撮影
- **インタラクティブ操作**: AIがヘッドレスChromeブラウザを操作し、リンクのクリック、フォーム入力、スクロールなどを実行。各アクション後にスクリーンショットで結果を確認
- **カスタマイズ可能なビューポート**: デスクトップ、タブレット、モバイル、印刷用のプリセット
- **高自律性モード**: AIは確認を求めずにアクションを即座に実行し、スムーズなブラウザ操作を実現

**インタラクティブブラウザセッション:**

AIにページ操作を依頼すると、Seleniumコンテナ内でヘッドレスブラウザセッションが開始されます。AIはリンクのクリック、テキスト入力、ページのスクロール、ページ間の移動など、1セッションあたり最大20アクションを実行できます。各アクション後にAIがスクリーンショットを受け取り、結果を確認します。

指示が曖昧な場合（例：「検索ボタンをクリックして」と言ったが候補が複数ある場合）、AIは候補要素に番号付きラベルを付けたスクリーンショットを表示し、どれを選ぶか確認します。

ブラウザの動作をリアルタイムで確認したい場合は、AIに非ヘッドレスモードの使用を依頼できます。noVNCを通じたリアルタイム表示が有効になります:

- **Electronアプリ**: メニューバーの **Open > noVNC を開く** からnoVNCウィンドウを開けます
- **開発モード**: ブラウザの別タブで `http://localhost:7900` を開いてください

**使用例:**
- `"https://github.com のスクリーンショットを撮って"` - 複数のスクリーンショットを撮影
- `"https://example.com を開いてAboutリンクをクリックして"` - インタラクティブ操作
- `"Googleで'monadic chat'を検索して"` - AIがページを操作
- `"https://example.com のモバイル版スクリーンショットを撮って"` - モバイルビューポートプリセットを使用

Web Insightの対応プロバイダーは冒頭の表を参照してください。


### Video Describer

![Video Describer app icon](../assets/icons/video-describer.png ':size=40')

動画コンテンツを分析し、その内容を説明するアプリケーションです。AIが動画コンテンツを分析し中で何が起こっているのかを詳細に説明します。

アプリ内部で動画からフレームを抽出し、それらをbase64形式のPNG画像に変換します。さらに、ビデオから音声データを抽出し、MP3ファイルとして保存します。これらに基づいてAIが動画ファイルに含まれる視覚および音声情報の全体的な説明を行います。

このアプリを使用するには、ユーザーは動画ファイルを`Shared Folder`に格納して、ファイル名を伝える必要があります。また、フレーム抽出のための秒間フレーム数（fps）を指定する必要があります。


### Knowledge Base

プロジェクト全体で共有される、会話とドキュメントの統合ライブラリです。Knowledge Base はすべての Monadic Chat アプリから参照可能なため、ここに保存した内容はどのチャットセッションからも検索・引用できます。

Knowledge Base は従来の PDF Navigator と Content Reader を置き換えるサブシステムです。会話のトランスクリプト、PDF、Office ファイル、Markdown、ソースコードを単一のインターフェースで扱えるようにまとめています。

**コンテンツの追加方法は 2 通り:**

1. **現在のチャットセッションを保存** — サイドバーの **Save** ボタンで、進行中の会話 (メッセージ + 参加者 + メタデータ) を Knowledge Base にシリアライズします。
2. **ファイルをインポート** — Knowledge Base Browser を開き、**Import file** ボタンから対応形式のファイルをアップロードします。ファイルは抽出・チャンク分割・埋め込みされ、検索・閲覧・リネーム可能な 1 件の会話エントリとして保存されます。

**インポート対応フォーマット:**

| フォーマット | 拡張子 | 備考 |
|---|---|---|
| Markdown | `.md`, `.markdown`, `.mdx` | YAML フロントマターはメタデータに昇格、ATX 見出しでセクション分割 |
| ソースコード | `.rb`, `.py`, `.js` / `.ts`, `.go`, `.java`, `.kt`, `.swift`, `.rs`, `.c` / `.cpp`, `.cs`, `.php`, `.sh`, `.sql` ほか | トップレベルの `def`/`class`/`func` などをチャンク境界とみなす。プログラミング言語は topic に記録 |
| PDF | `.pdf` | pdfplumber でテキストと表を抽出し Markdown 化。PDF メタデータの title が会話タイトルになる |
| Office | `.docx`, `.xlsx`, `.pptx` | Word の段落、Excel のシート、PowerPoint のスライド単位でチャンク化。Browse モーダルではフォーマット別アイコン (Word / Excel / PowerPoint) で表示 |

**スコープ (scope) モデル:**

各エントリは特定のアプリ＋プロバイダ (例: `Chat (OpenAI)`) か `Global` のいずれかにスコープされます。アプリ単位スコープのエントリは同一のアプリ＋プロバイダの組み合わせからのみ検索対象になります — `Chat (OpenAI)` で保存したエントリを `Chat (Claude)` から見ることはできません。`Global` のエントリは `library_search` ツール経由でどのアプリからでも検索可能です。Browse テーブルの rotate アイコン、または Conversation Viewer の **Make Global / Make app-only** ボタンで切り替えできます。

**その他の機能:**

- **再保存は既存エントリを上書き** — 同じセッションを 2 回目以降保存すると、新規作成ではなく既存エントリを更新します。再保存時はモーダルが「Update Conversation in Knowledge Base」モードに切り替わり、「Update」ボタンと警告バナーが表示されます。Reset / アプリ切替 / Browse からの削除でこの紐付けは解除されます。
- **AI によるタイトル提案** — 初回保存時、タイトル欄は現在のプロバイダーの LLM が会話の最初の数ターンから簡潔なタイトルを生成して自動入力します。これはデフォルトとしての提案であり、自由に上書きできます。提案結果はキャッシュされるため、保存をキャンセルして再度開いても再リクエストは発生しません。
- **リネーム** — Conversation Viewer を開き、タイトル横の鉛筆アイコンをクリック、編集して保存。Browse テーブルも即座に反映します。
- **インベントリと統計** — サイドバーには直近の保存とトータル件数。Browse モーダルでは検索・スコープフィルター・ソートが可能。
- **Conversation Viewer** — 行をクリックすると全メッセージの逐語表示。システムプロンプトは `<details>` で折り畳み済みで開きます。
- **RAG オプトイン (セッション単位)** — 任意のチャットセッションで **Use Knowledge Base for retrieval** トグルを ON にすると、LLM が応答中に `library_search` を呼び出せます。検索カスケードは現在アクティブなアプリのスコープフィルター (`scope_app IN [current_app, "Global"]`) を適用します。デフォルト OFF、最初のメッセージ送信でセッション中はロックされます。トグルの状態はセッションを跨いで永続化されるので、毎回切り替える必要はありません。
- **Privacy Filter との互換性** — Privacy Filter が有効なセッションでは、`library_search` が返すスニペットも同じ Privacy Pipeline でマスクされてから LLM に渡されます。Knowledge Base に平文で保存された PII が retrieval 経由で漏出しません。

?> Knowledge Base はローカル埋め込み (`multilingual-e5-base`) と Qdrant ベクトルストアを使用します。インポートは Python コンテナ内で実行され (pdfplumber / python-docx / openpyxl / python-pptx)、アップロードしたファイルは追跡用に `~/monadic/data/library/imports/` にも保存されます。ストレージ内部の詳細は[ベクトルデータベース](../docker-integration/vector-database.md)のドキュメントを参照してください。


## コード生成 :id=code-generation

### Code Interpreter

![Code Interpreter app icon](../assets/icons/code-interpreter.png ':size=40')

AIにプログラムコードを作成・実行させるアプリケーションです。プログラムの実行には、Dockerコンテナ内のPython環境が使用されます。実行結果として得られたテキストデータや画像は`Shared Folder`に保存されると共に、チャット上でも表示されます。

AIに読み込ませたいファイル（PythonコードやCSVデータなど）がある場合は、`Shared Folder` にファイルを保存して、Userメッセージの中でファイル名を指定してください。AIがファイルの場所を見つけられない場合は、ファイル名を確認して、現在のコード実行環境から利用可能であることを伝えてください。

?> **注意:** 日本語テキストを含むmatplotlibプロットでは、Pythonコンテナに日本語フォントサポート（Noto Sans CJK JP）がmatplotlibrcを通じて設定されています。

コードがプロット画像を生成した場合、AIは描画結果を視覚的に検証し、文字化け、ラベルの重なり、データの不整合などの問題を検出して、必要に応じてコードを自動修正・再実行します。

Code Interpreterの対応プロバイダーは冒頭の表を参照してください。プロバイダーによってツール呼び出しの仕様が異なるため、動作に差異が生じる場合があります。


### Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

プロフェッショナルなソフトウェアエンジニアとして機能するAIアシスタントです。コードの作成、ファイルの読み書き、プロジェクト管理など、開発作業全般をサポートします。

**主な機能:**
- コードの生成と編集
- Shared Folderへのファイル読み書き（write/appendモード対応）
- ディレクトリ内のファイルリスト表示
- 複雑なコーディングタスクへの対応

?> **注意:** Code InterpreterアプリはPythonコードを実行できますが、Coding Assistantアプリはコード生成とファイル操作に特化しており、コードの実行は行いません。


Coding Assistantの対応プロバイダーは冒頭の表を参照してください。


### Jupyter Notebook :id=jupyter-notebook

![Jupyter Notebook app icon](../assets/icons/jupyter-notebook.png ':size=40')

AIがJupyter Notebookを作成して、ユーザーからのリクエストに応じてセルを追加し、セル内のコードを実行するアプリケーションです。コードの実行には、Dockerコンテナ内のPython環境が使用されます。作成されたNotebookは`Shared Folder`に保存されます。セルがプロット画像を生成した場合、AIは出力結果を視覚的に検証し、問題があれば修正してから結果を提示します。

?> Jupyterノートブックを実行するためのJupyterLabサーバーの起動と停止は、AIエージェントに自然言語で依頼する他に、Monadic Chatコンソールパネルのメニューからも行うことができます（`Start JupyterLab`, `Stop JupyterLab`）。
<br /><br /><!-- SCREENSHOT: Actionsメニュー - Start JupyterLabとStop JupyterLabのメニュー項目が表示されている様子 -->

?> **注意:** サーバーモードでの制約については、[Web Interface - Server Mode](./web-interface.md#server-mode)を参照してください。

Jupyter Notebookの対応プロバイダーは冒頭の表を参照してください。


### Monadic Chat Help

![Help app icon](../assets/icons/help.png ':size=40')

Monadic Chat用のAI駆動ヘルプアシスタントです。プロジェクトのドキュメントに基づいて、機能、使用方法、トラブルシューティングについての質問に任意の言語で文脈に応じた支援を提供します。

ヘルプシステムは、英語のドキュメントから作成された事前構築されたナレッジベースを使用します。質問をすると、関連情報を検索し、公式ドキュメントに基づいて正確な回答を提供します。ヘルプシステムのアーキテクチャの詳細については、[ヘルプシステム](../advanced-topics/help-system.md)を参照してください。


## 特殊アプリ :id=specialized-apps

### Auto Forge (Artifact Builder) :id=auto-forge

![Auto Forge app icon](../assets/icons/auto-forge.png ':size=40')

AIオーケストレーションを通じて、完全なWebアプリケーションやコマンドラインツールを自律的に作成します。Auto Forge（「Artifact Builder」として販売）は、外部依存関係なしに単一ファイルのHTMLアプリケーションまたはスタンドアロンスクリプトを生成します。

**主な機能：**
- **自律的計画**: AIが要件を分析し、詳細な実装計画を作成
- **単一ファイル出力**: Webアプリは単一のHTMLファイルとして、CLIツールはスタンドアロンスクリプトとして出力
- **プロジェクト管理**: タイムスタンプとUnicode名をサポートした自動整理
- **オプションのデバッグ**: WebアプリケーションのSeleniumベースの自動テスト

詳細なドキュメントは[Auto Forge](../apps/auto_forge.md)を参照してください。

Auto Forgeの対応プロバイダーは冒頭の表を参照してください。


### Music Lab :id=music-lab

![Music Lab app icon](../assets/icons/music.png ':size=40')

コード・スケール・音程・進行を実際に鳴らし、バッキングトラックを生成しながら音楽理論を手を動かして学ぶラボです。AIが音楽理論の概念を解説し、音声サンプルをブラウザ内で直接再生します。既存の録音の音楽性や演奏を評価したい場合は、Music Analystをご利用ください。

**主な機能：**
- **音声/MIDI分析**: 音声ファイル（mp3, wav, m4a, ogg, flac）やMIDIファイル（mid, midi）をアップロードして、テンポ・キー・拍子・コード進行・楽曲構造を検出。MIDI分析ではトラック・楽器情報も抽出
- **音声再生**: コード、スケール、音程、進行を楽譜表示付きでブラウザ内MIDI合成により再生
- **バッキングトラック**: スタイル別パターン（ジャズ、ボサノバ、ポップ、ロック、バラード）による複数楽器のバッキングトラック生成
- **アルゴリズムメロディ**: コードスケール理論、ユークリッドリズム、コンターシェイピングによる自動メロディ生成（lyrical、rhythmic、jazz、latin、gentleの5スタイル）
- **ギター特有パターン**: ボサノバ・アルペジオ、ロック・パワーコード、バラード・フィンガーピッキング
- **ウォーキングベース**: クロマティック・アプローチノート付きジャズ・ウォーキングベース、ボサノバ2ビートフィール
- **包括的な音楽理論**: 46種のコード、15種のスケール、全チャーチモード、スラッシュコード、エンハーモニック・スペリング対応

音声分析にはオプションの**音声分析**パッケージ（librosa + madmom）が必要です。**Actions → Install Options**で有効化し、Pythonコンテナを再ビルドしてください。

Music LabはOpenAI、Claude、Gemini、Grokで利用可能です。

### Music Analyst :id=music-analyst

![Music Analyst app icon](../assets/icons/music.png ':size=40')

録音された演奏を、2つの相補的な観点から評価します：客観的な計測特徴と、楽曲・演奏に対する解釈的な講評です。コードやスケールを鳴らして音楽理論を学ぶ場合は、Music Labをご利用ください。

**主な機能：**
- **客観的特徴**: アップロードした音声またはMIDIファイルから、信号処理によりテンポ・キー・拍子・コード進行・楽曲構造を抽出
- **解釈的講評**: Geminiが音声を聴き、全体の性格やムード、ジャンルや楽器編成、演奏の質（表現、ダイナミクス、フレージング、タイミング、エネルギー）について、長所・短所・総合評価とともにコメント
- **相補的な2つの観点**: 客観的な事実、解釈的な講評、またはその両方を要求可能。両者は明確に分離されたセクションとして提示されます

解釈的講評は音声をモノラル・低帯域で分析するため、音質・ミックス/マスタリング・ステレオ像は評価しません。正確なテンポやキーは客観的特徴分析から得られます。講評は実音声（mp3, wav, m4a, ogg, flac）が対象で、MIDIファイルは客観的分析のみ対応です。

客観的特徴分析にはオプションの**音声分析**パッケージ（librosa + madmom）が必要です。**Actions → Install Options**で有効化し、Pythonコンテナを再ビルドしてください。

Music AnalystはGeminiで利用可能です。

### Document Generator :id=document-generator

![Document Generator app icon](../assets/icons/document-generator.png ':size=40')

AIを使用してOfficeドキュメントを生成します。Excel、PowerPoint、Word、PDFなど。ファイルは共有フォルダに自動保存されます。

**主な機能：**
- **Excel (.xlsx)**: データテーブル、チャート、数式、複数シート
- **PowerPoint (.pptx)**: ビジュアルレイアウトを備えたプロフェッショナルなスライド
- **Word (.docx)**: 見出し、リスト、表を含むフォーマット済みドキュメント
- **PDF**: 適切なフォーマットのプロフェッショナルなドキュメント

Document Generatorは現在Claudeで利用可能です。


