---
title: Monadic Chat
layout: default
---

# 概要

[English](/monadic-chat/overview) |
[日本語](/monadic-chat/overview_ja)

<img src="./assets/images/screenshot-01.png" width="700px"/>

🌟 **Monadic Chat**はOpenAIのChat APIとWhisper API、そしてプログラミング言語のRubyを活用して高機能なチャットボットを作成・使用するためのフレームワークです。

⚠️  **ご注意**

本ソフトウェアは現在開発中であり、頻繁に変更される可能性があります。一部の機能はまだ不安定な場合がありますので、使用する際は十分に注意してください。

📢 **協力の呼びかけ**

本ソフトウェアの改善に役立つ貢献（コードの改善、テストの追加、ドキュメントの追加など）を歓迎します。よろしければご協力をお願いいたします。

## 主な特徴

### 基本構造

- 🤖 OpenAIのChat API（**GPT-3.5**または**GPT-4**）を使用し、ターン数制限のないチャットを実現
- 👩‍💻 **Docker Desktop**を使用して、Mac、Windows、Linuxにインストール可能

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

### 画像生成

- 🖼️ DALL·E 2 APIを利用した**画像生成**

### 設定と拡張

- 💡 **APIパラメータ**と**システムプロンプト**を指定して、AIエージェントの設定や動作をカスタマイズ
- 💎 プログラミング言語**Ruby**を使用した機能拡張（基本アプリの開発）

### メッセージの編集

- 📝 過去のメッセージの**再編集**
- 🗑️ 特定のメッセージの**削除**
- 📜 新規メッセージの**ロール**設定（ユーザー、アシスタント、システム）

### 高度な機能

- 🪄 AIアシスタントからのメインのレスポンスに加えて、背後で追加のレスポンスを取得し、事前定義されたJSONオブジェクト内に値を格納することで会話の**状態**を実現

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
