<div align="center">

<img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/monadic-chat-logo.png" width="700px" alt="Monadic Chat Logo">

<a href="https://github.com/yohasebe/monadic-chat/releases"><img src="https://img.shields.io/github/v/release/yohasebe/monadic-chat?style=for-the-badge" alt="Release"></a>
<a href="LICENSE"><img src="https://img.shields.io/github/license/yohasebe/monadic-chat?style=for-the-badge" alt="License"></a>
<img src="https://img.shields.io/badge/tests-passing-success?style=for-the-badge" alt="Tests">

  ---

  **🎯 機能** · [マルチモーダル](https://yohasebe.github.io/monadic-chat/#/ja/basic-usage/basic-apps#マルチモーダル機能) · [PDFナレッジベース](/ja/basic-usage/pdf_storage.md) · [Web検索](https://yohasebe.github.io/monadic-chat/#/ja/basic-usage/basic-apps#web検索統合) · [コード実行](https://yohasebe.github.io/monadic-chat/#/ja/basic-usage/basic-apps#code-interpreter) · [音声チャット](https://yohasebe.github.io/monadic-chat/#/ja/basic-usage/basic-apps#voice-chat)

  **🤖 対応プロバイダー** · OpenAI · Claude · Gemini · Mistral · Cohere · Perplexity · xAI · DeepSeek · Ollama

  **🛠 使用技術** · Ruby · Electron · Docker · PostgreSQL · WebSocket

  ---

  <img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/basic-architecture-ja.png" width="800px" alt="Monadic Chat Architecture">

</div>

## 概要

**Monadic Chat**は、インテリジェントなチャットボットを作成・利用するためのローカル環境で動作するWebアプリケーションです。Docker上の実際のLinux環境をAIモデルに提供することで、外部ツールを必要とする高度なタスクを実行できます。音声インタラクション、画像・動画処理、AIどうしの会話をサポートし、AIアプリケーションプラットフォームとして、またAI駆動アプリケーション開発のフレームワークとして機能します。

 **コンテキストを持つ会話**: 関数型プログラミングのモナドが値をコンテキストでラップするように、Monadic Chatの会話は構造化されたメタデータ（推論、トピック、メモ）を持つことができます。

**データとしての会話**: 会話は、Webサービスに閉じ込められた一時的なセッションではなく、あなたが所有する永続的でポータブルなデータです。会話履歴を自由に編集、削除、エクスポート、インポートできます。

**Mac、Windows、Linux対応**

📖 **[ドキュメント](https://yohasebe.github.io/monadic-chat)** (英語/日本語) · 📋 **[変更履歴](https://yohasebe.github.io/monadic-chat/#/ja/changelog)**

## はじめよう

### インストール

1. **ダウンロード**: [Releases](https://github.com/yohasebe/monadic-chat/releases)から、お使いのプラットフォーム用のインストーラーをダウンロード
   - macOS: `.dmg` ファイル (Apple Silicon または Intel)
   - Windows: `.exe` インストーラー
   - Linux: `.deb` パッケージ (Debian/Ubuntu)

2. **インストール**してアプリケーションを起動

3. **APIキーの設定**: Settings で設定

4. **使い始める**: 組み込みアプリケーションを使用、または独自のアプリを作成

📖 **詳細なインストールガイド**: [インストール](https://yohasebe.github.io/monadic-chat/#/ja/getting-started/installation)

### クイックスタート

インストール後:

1. **Start** をクリックしてDocker環境を起動
2. サイドバーからアプリを選択 (まずは **Chat** または **Voice Chat** を試してください)
3. AIプロバイダーを選択 (OpenAI、Claude、Geminiなど)
4. チャット開始！

オフライン利用の場合は、[Ollama](https://ollama.com/) をインストールしてプロバイダーとして選択してください。

## なぜMonadic Chatなのか？

WebベースのAIサービスやIDE統合型アシスタントとは異なり、Monadic Chatは**ローカル実行AIプラットフォーム**として以下を提供します：

1. **好きなツールを使用**: 実際のDockerコンテナにアクセスし、コード実行、パッケージインストール、ファイル永続化が可能。

2. **ローカルデータストレージ**: 会話、コード、ファイルをクラウドではなくローカルマシン上に保存。Ollamaを使用すればオフライン動作も可能。

3. **拡張可能なプラットフォーム**: 単なるチャットボットではなく、Monadic DSLを使ってカスタムAIアプリケーションを構築するフレームワーク。

4. **プロバイダー非依存**: 9つのAIプロバイダーを切り替え可能。各タスクに最適なモデルを選択。

## 機能

### 主な特徴

- **🤖 複数プロバイダー対応**: OpenAI、Claude、Gemini、Mistral、Cohere、Perplexity、xAI、DeepSeek、Ollama
- **🐧 実際のLinux環境**: AIエージェントが実際のDockerコンテナでコード実行、パッケージインストール、ツール使用
- **💬 高度な会話管理**: 構造化されたコンテキストで会話履歴を編集、エクスポート/インポート、追跡
- **🎙️ 音声インタラクション**: 複数プロバイダーによるテキスト読み上げ・音声認識、話者識別機能
- **🖼️ 画像・動画**: 最新AIモデルによる画像・動画の生成、編集、分析
- **📄 PDFナレッジベース**: ドキュメントをローカル (PGVector) またはクラウド (OpenAI Vector Store) に保存・検索
- **🌐 Web検索統合**: OpenAI、Claude、Gemini、Grok、Perplexityでネイティブ検索
- **🔄 自動アップデート**: アプリ内通知とシームレスなアップデートダウンロード

### 主要アプリケーション

Chat · Chat Plus · Code Interpreter · Coding Assistant · Research Assistant · Voice Chat · Jupyter Notebook · Auto Forge · Concept Visualizer · Syntax Tree · Video Generator · Math Tutor · PDF Navigator · Image Generator · Language Practice

📖 **全リストと詳細**: [基本アプリ](https://yohasebe.github.io/monadic-chat/#/ja/basic-usage/basic-apps)（全31アプリ）

### 拡張性

- **Monadic DSL**: 宣言的構文でカスタムアプリケーションを作成
- **Docker統合**: 独自のコンテナとツールを追加
- **Ruby & Python**: 使い慣れた言語で機能拡張
- **MCPサーバー**: JSON-RPC 2.0経由で外部ツールやサービスと連携

📖 **開発ガイド**: [高度なトピック](https://yohasebe.github.io/monadic-chat/#/ja/advanced-topics/)

## ドキュメント

- 📖 **[ドキュメント](https://yohasebe.github.io/monadic-chat)** (英語/日本語)
- 🚀 **[はじめよう](https://yohasebe.github.io/monadic-chat/#/ja/getting-started/installation)**
- 📚 **[基本操作](https://yohasebe.github.io/monadic-chat/#/ja/basic-usage/basic-apps)**
- 🐳 **[Docker連携](https://yohasebe.github.io/monadic-chat/#/ja/docker-integration/basic-architecture)**
- 💡 **[高度な機能](https://yohasebe.github.io/monadic-chat/#/ja/advanced-topics/)**
- 📖 **[リファレンス](https://yohasebe.github.io/monadic-chat/#/ja/reference/configuration)**
- ❓ **[よくある質問](https://yohasebe.github.io/monadic-chat/#/ja/faq)**

## 開発者

長谷部 陽一郎（Yoichiro HASEBE）
[yohasebe@gmail.com](mailto:yohasebe@gmail.com)

## ライセンス

このソフトウェアは[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)の条件に基づいてオープンソースとして利用可能です。
