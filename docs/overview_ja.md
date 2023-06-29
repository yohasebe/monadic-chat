---
title: Monadic Chat
layout: default
---

# Overview (JA)

[English](/monadic-chat-web/overview) |
[日本語](/monadic-chat-web/overview_ja)

<img src="./assets/images/screenshot-01.png" width="700px"/>

**Monadic Chat**はOpenAIのChat APIとWhisper API、そしてプログラミング言語のRubyを活用して高機能なチャットボットを作成・使用するためのフレームワークです。

## 基本構造

- 🤖 OpenAIのChat API（**GPT-3.5**または**GPT-4**）を使用し、ターン数制限のないチャットを実現
- 👩‍💻 **Docker Desktop**を使用して、Mac、Windows、Linuxにインストール可能

## データ管理

- 💾 会話データの**エクスポート/インポート**
- 💬 文脈データとしてAPIに送信するメッセージ（**アクティブメッセージ**）数の指定
- 🔢 **PDFファイル**内のデータから**テキスト埋め込み**生成

## 音声インタラクション

- 🎙️ Whisper APIを使用した、**マイク音声認識**
- 🔈 AIアシスタントによるレスポンス**テキスト読み上げ**
- 🗺️ テキスト読み上げのための**自動言語検出**
- 🗣️ テキスト読み上げのための**言語とボイス**の選択
- 😊 音声認識とテキスト読み上げを使用した、AIエージェントとの**インタラクティブな会話**

## 設定と拡張

- 💡 **APIパラメータ**と**システムプロンプト**を指定して、AIエージェントの設定や動作をカスタマイズ
- 💎 プログラミング言語**Ruby**を使用した機能拡張（Base Appの開発）

## メッセージの編集

- 📝 過去のメッセージの**再編集**が可能
- 🗑️ 特定のメッセージの**削除**が可能
- 📜 新規メッセージのロール（ユーザー、アシスタント、システム）設定

## 高度な機能

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
