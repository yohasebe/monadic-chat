---
title: Monadic Chat
layout: default
---

# 基本アプリ
{:.no_toc}

[English](/monadic-chat/apps) |
[日本語](/monadic-chat/apps_ja)

## Table of Contents
{:.no_toc}

1. toc
{:toc}

以下は、使用可能な基本アプリ（base app）の一覧です。これらのいずれかを選択し、パラメータを変更したり初期プロンプトを書き換えたりすることで、AIエージェントの動作を調整することができます。調整した設定を外部のJSONファイルにエクスポート/インポートすることもできます。
## Chat

<img src="./assets/icons/chat.png" width="40px"/>Monadic Chatの標準アプリケーションです。ChatGPTと基本的に同じような方法で使用することができます。 

## Language Practice

<img src="./assets/icons/language-practice.png" width="40px"/>AIアシスタントの音声で会話が始まる言語学習アプリケーションです。アシスタントの音声は合成音声で再生されます。Enterキーを押すと音声入力が開始します。再度Enterキーを押すと音声入力が停止します。

## Language Practice Plus

<img src="./assets/icons/language-practice-plus.png" width="40px"/>AIアシスタントの音声で会話が始まる言語学習アプリケーションです。アシスタントの音声は合成音声で再生されます。Enterキーを押すと音声入力が開始します。再度Enterキーを押すと音声入力が停止します。 通常のレスポンスに加えて、学習言語のアドバイスが示されます。アドバイスは読み上げられず、通常のテキストとして表示されます。

## Novel Writer

<img src="./assets/icons/novel.png" width="40px"/> アシスタントと共同で小説を執筆するためのアプリケーションです。プロンプトでテーマ、トピック、またはイベントを提示すると、それらを含んだパラグラフを書きます。

## PDF Navigator

<img src="./assets/icons/pdf-navigator.png" width="40px"/>PDFファイルを読み込み、AIアシスタントがその内容に基づいてユーザーの質問に答えるアプリケーションです。`PDF Upload`ボタンをクリックしてファイルを指定します。ファイルの内容は、`max_tokens`で指定した長さに収まるサイズのセグメントに分割され、各セグメントのテキスト埋め込みが生成されます。ユーザーからメッセージを受け取ると、そのメッセージのテキスト埋め込みに最も近いセグメントがGPTに与えられ、その内容に基づいた回答が行われます。

<img src="./assets/images/rag.png" width="600px"/>

## Translate

<img src="./assets/icons/translate.png" width="40px"/>AIアシスタントが、ユーザーの入力テキストを別の言語に翻訳します。アシスタントは最初に対象言語を尋ねます。AIアシスタントに特定の訳語を使わせたいときは、入力テキストの該当部分の後ろに括弧を付け、括弧内にその訳語をあらかじめ指定することができます

## Voice Chat

<img src="./assets/icons/voice-chat.png" width="40px"/>OpenAIのWhisper APIとブラウザのテキスト読み上げAPIを使用して、音声を通じてチャットすることができます。初期プロンプトはChatアプリと同じです。音声認識機能を使用するためにはGoogle ChromeまたはMicrosoft Edgeを使用する必要があります。

## Wikipedia

<img src="./assets/icons/wikipedia.png" width="40px"/> 基本的にChatと同じですが、言語モデルのカットオフ時点以降に発生したイベントなど、GPTが答えられない質問については、Wikipediaを検索して回答します。クエリが非英語の場合、Wikipediaの検索は英語で行われ、結果は元の言語に翻訳されます。

## Linguistic Analysis

<img src="./assets/icons/linguistic-analysis.png" width="40px"/>指定された構造のJSONオブジェクトを「状態」とみなして、これを更新するタイプのアプリです。ユーザーへのレスポンスとして、入力文の統語構造を返します。その背後でtopic、sentence_type、sentimentの状態値を更新します。

## Math Tutor

<img src="./assets/icons/math.png" width="40px"/> AIチャットボットがMathJaxの数学表記を使用して応答するためのアプリケーションです。このアプリは数学的表記を表示することができますが、数学の計算能力はOpenAIのGPTモデルに基づいており、単純な計算においても誤りが生じ得ることが知られています。計算の正確性が必要な場合には注意して使用してください。

## Image Generator

<img src="./assets/icons/image-generator.png" width="40px"/> 画像生成のためのアプリです。初期プロンプトを入力するとOpenAIのDALL·E APIを用いて画像を生成します。会話のモデルとしてGPT 4.0を指定すると、AI chatbotとのインタラクションを通じてプロンプトを少しずつ改善して、望む画像を得ることができます。

## Mail Composer

<img src="./assets/icons/mail-composer.png" width="40px"/> AIアシスタントと共同でメールの文章を書くためのアプリケーションです。ユーザーの要望や仕様に合わせてアシスタントが文面や改善案を提案します。 

## Document Reader

<img src="./assets/icons/document-reader.png" width="40px"/> 効率的に文書を読むためのアプリケーションです。アシスタントが文書を読み上げ、その内容を最初から最後まで小さなまとまりに分割して説明します。ユーザーは文書の内容について質問することができ、アシスタントは文書の内容に基づいてそれに答えます。

## Diagram Draft

<img src="./assets/icons/diagram-draft.png" width="40px"/> ダイアグラムの雛形を作成するためのアプリケーションです。ユーザーの入力をもとに、アシスタントがMermaidライブラリを使って図を作成します。ユーザーはダイアグラムの種類と内容を指定することで、アシスタントにダイアグラムの作成を依頼することができます。

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
