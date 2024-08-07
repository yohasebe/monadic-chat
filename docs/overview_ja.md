---
title: Monadic Chat
layout: default
---

# 概要

[English](/monadic-chat/overview) |
[日本語](/monadic-chat/overview_ja)

<img src="./assets/images/monadic-chat-architecture.png" width="800px"/>


## これは何？

**Monadic Chat** は、インテリジェントなチャットボットを作成・利用するためのWebアプリケーションフレームワークです。GPT-4やその他のLLMにDocker上のLinux環境を与え、外部ツールを必要とする高度なタスクを実行させることができます。また、音声インタラクション、画像・動画の認識と生成、AI同士のチャットをサポートしており、AIを使うだけでなく、活用した様々なアプリケーションの開発や研究にも役立ちます。

[更新情報](https://github.com/yohasebe/monadic-chat/blob/main/CHANGELOG.md)

## 主な特徴

### 基本構造

- 🤖 OpenAIのChat API（**GPT-4**）を使用したチャット機能
- 👩‍💻 **Electron**を用いたGUIアプリとしてMacおよびWindowsにインストール可能
- 🌐 **Webアプリ**としてブラウザ上で利用可能
- 👩💬 🤖💬 **human↔️AI chat**と**AI↔️AI chat**の両方をサポート

### AI + Linux環境

- 🐧 AIに自由に利用できる**Linux環境**（Ubuntu）を提供
- 🐳 **Dockerコンテナ**を通じてLLMから利用できるツール群
  - Python (+ pip) for tool/function calls
  - Ruby (+ gem) for tool/function calls
  - PGVector (+ PostgreSQL) for DAG using vector representation
  - Selenium (+ Chrome/Chromium) for web scraping
- 📦 各コンテナは**SSH**接続による管理が可能
- 📓 Pythonコンテナ上では**Jupyter Notebook**を起動可能

### データ管理

- 💾 会話データの**エクスポート/インポート**
- 💬 文脈データとしてAPIに送信するメッセージ（**アクティブメッセージ**）数の指定
- 🔢 **PDFファイル**内のデータから**テキスト埋め込み**生成

### 音声インタラクション

- 🎙️ Whisper APIを使用した、**マイク音声認識**
- 🔈 AIアシスタントによるレスポンス**テキスト読み上げ**
- 🗺️ テキスト読み上げのための**自動言語検出**
- 🗣️ テキスト読み上げのための**言語とボイス**の選択
- 😊 音声認識とテキスト読み上げを使用した、AIエージェントとの**インタラクティブな会話**
- 🎧 AIアシスタントによる読み上げ音声を**MP3オーディオ**ファイルとして保存

### 動画・画像の認識と生成

- 🖼️ DALL·E 3 APIを利用した**画像生成**
- 👀 アップロードされた**画像の認識と説明**
- 📚 **複数の画像**のアップロードと認識
- 🎥 アップロードされた**動画の内容と音声の認識と説明**

### 設定と拡張

- 💡 **APIパラメータ**と**システムプロンプト**を指定して、AIエージェントの設定や動作をカスタマイズ
- 💎 プログラミング言語**Ruby**を使用した機能拡張
- 🐍 プログラミング言語**Python**を使用した機能拡張
- 🌎 Seleniumを使用した**Webスクレイピング**

### メッセージの編集

- 📝 過去のメッセージの**再編集**
- 🗑️ 特定のメッセージの**削除**
- 📜 新規メッセージの**ロール**設定（ユーザー、アシスタント、システム）

### 複数のLLM APIに対応

- 👥 下記のLLMのAPIに対応
  - OpenAI GPT-4
  - Google Gemini
  - Anthropic Claude
  - Cohere Command R
  - Mistral AI
- 🤖💬🤖 AI↔️AI Chatは以下の組み合わせで利用可能

   | AI-Assistant     | | AI-User               |
   |:-----------------|-|:----------------------| 
   | OpenAI GPT-4     |↔️| OpenAI GPT-4 or GPT4o |
   | Google Gemini    |↔️| OpenAI GPT-4 or GPT4o |
   | Anthropic Claude |↔️| OpenAI GPT-4 or GPT4o |
   | Cohere Command R |↔️| OpenAI GPT-4 or GPT4o |
   | Mistral AI       |↔️| OpenAI GPT-4 or GPT4o |

### モナドとしての会話の管理

- ♻️   AIアシスタントからのメインのレスポンスに加えて、背後で追加のレスポンスを取得し、事前定義されたJSONオブジェクト内の値を更新することで会話の（見えない）**状態の管理**が可能

<script src="https://cdn.jsdelivr.net/npm/jquery@3.5.0/dist/jquery.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/lightbox2@2.11.3/src/js/lightbox.js"></script>

---

<script>
  function copyToClipBoard(id){
    var copyText =  document.getElementById(id).innerText;
    document.addEventListener('copy', function(e) {
        e.clipboardData.setData('text/plain', copyText);
        e.preventDefault();
      }, true);
    document.execCommand('copy');
    alert('copied');
  }
</script>
