# チャット・アシスタントアプリ

汎用的な会話・アシスタント系のアプリです。標準チャットやメタデータ付きチャット、音声チャットのほか、百科事典検索・数学・セカンドオピニオン・リサーチ・Monadic Chat自体のヘルプを担当するアシスタントを含みます。

## Chat

![Chat app icon](../assets/icons/chat.png ':size=40')

標準的なチャットアプリケーションです。ユーザーが入力したテキストに対して、AIが適切な絵文字とともに応答します。ツール/関数呼び出しに対応したモデルではWeb検索も利用できます。各プロバイダーが組み込みのネイティブ検索とTavily API（`TAVILY_API_KEY`が必要）のどちらを使用するかは、[プロバイダー機能概要の表](../basic-usage/basic-apps.md#provider-capabilities)を参照してください。

また、メッセージ入力エリアの`URLから読込`機能により、プロバイダーに関係なく、Seleniumベースのスクレイピングで任意のURLのコンテンツを抽出できます。

本アプリの対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Chat Plus

![Chat app icon](../assets/icons/chat-plus.png ':size=40')

Chatアプリの拡張版で、"monadic" な振る舞いを示します。AIの回答の背後で下記の情報を保持し、随時更新します。

- reasoning: 回答の作成における動機づけと根拠など
- topics: ここまでの会話で取り上げられたトピック
- people: 会話に関連する人物
- notes: 会話で取り上げられた重要なポイント


## Voice Chat :id=voice-chat

![Voice Chat app icon](../assets/icons/voice-chat.png ':size=40')

選択したプロバイダーの音声認識APIで音声入力を行い、音声設定パネルで選択したText-to-Speechプロバイダーで音声出力を行う、音声チャットアプリケーションです。出力の既定はブラウザ内蔵のWeb Speech APIで、APIキーは不要です。代わりにプロバイダーのTTSエンジン（OpenAI、ElevenLabs、Gemini、Mistral、xAI Grok）を選択することもできます。初期プロンプトは基本的にChatアプリと同じです。

音声入力中は波形が表示され、入力終了後には認識の「確からしさ」を示すp-value（0〜1の値）が表示されます。詳細は[音声入力](../basic-usage/message-input.md#speech-input)を参照してください。

Voice Chatの対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。チャットプロバイダーとTTSプロバイダーの組み合わせは自由です（例: Claudeで会話しながらxAI Grokで音声出力）。音声入出力の設定については[音声設定パネル](../basic-usage/web-interface.md#speech-settings-panel)を参照してください。

**Expressive Speech**: Auto Speech をオンにし、対応する TTS プロバイダーを選択すると、Text-to-Speech Provider ドロップダウンの下に✨ **Expressive Speech** バッジが表示され、アシスタントの応答に表情豊かな音声表現（間・笑い・発話指示など）が加わります。これらはチャット履歴のテキストには一切現れません。仕組みはプロバイダーごとに自動選択されます — 各プロバイダーの実装方式については[音声設定パネル](../basic-usage/web-interface.md#speech-settings-panel)を参照してください。


## Wikipedia

![Wikipedia app icon](../assets/icons/wikipedia.png ':size=40')

基本的にChatと同じですが、言語モデルのカットオフ日時以降に発生したイベントに関する質問など、AIが回答できない質問に対しては、Wikipediaを検索して回答します。問い合わせが英語以外の言語の場合、Wikipediaの検索は英語で行われ、結果は元の言語に翻訳されます。


## Math Tutor

![Math Tutor app icon](../assets/icons/math-tutor.png ':size=40')

AIチャットボットが [KaTeX](https://katex.org/) の数式表記を用いて応答するアプリケーションです。数式の表示が必要なやりとりを行うのに適しています。

!> **注意:** LLMの数学的計算能力には制約があり、誤った結果が出力されることがあります。計算の正確性が求められる場合は、Code Interpreterアプリなどで実際に計算を行うことをお勧めします。


## Second Opinion

![Second Opinion app icon](../assets/icons/second-opinion.png ':size=40')

このアプリは2段階の相談プロセスを提供します。**ステップ1**: 質問をすると、AIから初期回答を受け取ります。**ステップ2**: 「セカンドオピニオンを求める」「別の視点で確認して」などのフレーズで検証を依頼すると、別のAIプロバイダーが初期回答をレビューしコメントします。これにより、回答の正確性を確保し、複雑なトピックについて多様な視点を得ることができます。

Second Opinionアプリの対応状況は[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Research Assistant

![Research Assistant app icon](../assets/icons/research-assistant.png ':size=40')

アカデミックな研究や科学的研究をサポートするために設計されたアプリケーションで、強力なウェブ検索機能を持つインテリジェントな研究アシスタントとして機能します。オンラインソースから情報を取得・分析し、最新情報の検索、事実の検証、トピックの包括的な調査を支援します。研究アシスタントは、信頼性の高い詳細な洞察、要約、説明を提供し、あなたの探究を進めます。

Research Assistantの対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。Web検索でネイティブ検索とTavily API（`TAVILY_API_KEY`が必要）のどちらが使われるかは[プロバイダー機能概要の表](../basic-usage/basic-apps.md#provider-capabilities)のとおりです。SeleniumベースのURLコンテンツ抽出は全プロバイダーで利用できます。

> **注意**: GeminiのResearch Assistantは、ネイティブGoogle検索グラウンディングの代わりに内部ウェブ検索エージェント（`gemini_web_search`）を使用します。これにより、GeminiのAPI制限を回避し、ウェブ検索とファイル操作・プログレストラッキングを同時に利用できます。

詳細については、上記のChatアプリの説明または[URLからのテキスト読み込み](../basic-usage/message-input.md#reading-text-from-urls)を参照してください。


## Monadic Chat Help

![Help app icon](../assets/icons/help.png ':size=40')

Monadic Chat用のAI駆動ヘルプアシスタントです。プロジェクトのドキュメントに基づいて、機能、使用方法、トラブルシューティングについての質問に任意の言語で文脈に応じた支援を提供します。

ヘルプシステムは、英語のドキュメントから作成された事前構築されたナレッジベースを使用します。質問をすると、関連情報を検索し、公式ドキュメントに基づいて正確な回答を提供します。ヘルプシステムのアーキテクチャの詳細については、[ヘルプシステム](../advanced-topics/help-system.md)を参照してください。
