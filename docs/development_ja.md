---
title: Monadic Chat
layout: default
---

# 開発
{:.no_toc}

[English](/monadic-chat/development) |
[日本語](/monadic-chat/development_ja)

## Table of Contents
{:.no_toc}

1. toc
{:toc}

## Docker Desktopを使わないインストール

### Ruby

バージョン3.1以上を推奨

### Rust

tiktoken gemを使ったトークン数の計算にRustが必要

### PostgreSQL + pgvector

PostgreSQLとその上でVector DBを使うためのモジュールpgvectorが必要

- [pgvector](https://github.com/pgvector/pgvector)

### インストール

```bash
$ git clone https://github.com/yohasebe/monadic-chat.git
$ cd monadic-chat
$ bundle install
$ chmod -R +x ./bin
```

### Monadic Chatの起動・停止・再起動

`start`

```bash
# pwd: monadic-chat
$ ./bin/monadic start
```

`stop`

```bash
# pwd: monadic-chat
$ ./bin/monadic stop
```

`restart`

```bash
# pwd: monadic-chat
$ ./bin/monadic restart
```

### Monadic Chatのアップデート

```bash
# pwd: monadic-chat
$ git pull
```

## 基本アプリの開発

### ディレクトリ／ファイル構成

```text
apps
├── chat
│   └── chat_app.rb
├── code
│   └── code_app.rb
├── language_practice
│   └── language_practice_app.rb
├── language_practice_plus
│   └── language_practice_plus_app.rb
├── linguistics
│   └── linguistics_app.rb
├── math
│   └── math_app.rb
├── novel
│   └── novel_app.rb
├── pdf
│   └── pdf_app.rb
├── translate
│   └── translate_app.rb
├── voice_chat
│   └── voice_chat_app.rb
├── wikipedia
│   └── wikipedia_app.rb
└── NEW_APP_FOLDER
    └── NEW_APP.rb
```

### アプリ記述ファイルの例

```ruby
# すべての基本アプリはMonadicAppクラスを継承する
class AppName < MonadicApp
  # iconは<i>タグで表現する（FontAwesomeを利用）
  def icon
    "<i class='fas fa-comments'></i>"
  end

  # descriptionはアプリの説明
  def description
    "This is the standard application for monadic chat. It can be used in basically the same way as ChatGPT."
  end

  # initial_promptは初期システムプロンプトとして使用される
  def initial_prompt
    text = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it. Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response.
    TEXT
    text.strip
  end

  # settingsはアプリの設定を表すハッシュ
  def settings
    {
      # 画面に表示されるアプリ名
      "app_name": "Chat",
      # 画面に表示されるアプリのアイコン（上で定義したicon）
      "icon": icon,
      # アプリの説明（上で定義したdescription）
      "description": description,
      # デフォルトのシステムプロンプト（上で定義したinitial_prompt）
      "initial_prompt": initial_prompt,
      # デフォルトのOpenAIのGPTのモデル
      "model": "gpt-3.5-turbo",
      # デフォルトのtemperature
      "temperature": 0.5,
      # デフォルトのtop_p
      "top_p": 0.0,
      # デフォルトのmax_tokens
      "max_tokens": 1000,
      # デフォルトのコンテクストサイズ（activeとして保持されるメッセージ数）
      "context_size": 10,
      # デフォルトのeasy_submit（trueの場合、ユーザーがEnterを押すと送信される）
      "easy_submit": false,
      # デフォルトのauto_speech（trueの場合、レスポンスを自動的に読み上げる）
      "auto_speech": false,
      # デフォルトのinitiate_from_assistant（trueの場合、まずアシスタントから発言する）
      "initiate_from_assistant": false,
      # PDFをアップロードしてVector DBに格納するフォームを表示するかどうか
      "pdf": false,
      # $$で囲まれた数式をMathJaxでレンダリングするかどうか（インラインの数式は$で囲む）
      "mathjax": false,
      # 関数呼び出しを行う場合、関数の定義を記述する（下記参照）
      "functions": [],
      # Monadicモードを使用する（下記参照）
      "monadic": false
    }
  end
end
```

### Rubyでの関数呼び出し

🚧 UNDER CONSTRUCTION


### Monadicモードについて

🚧 UNDER CONSTRUCTION

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
