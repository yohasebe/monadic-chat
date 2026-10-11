# 文章・ドキュメント作成アプリ

小説・メール・スピーチ原稿からOfficeドキュメントまで、文章コンテンツの作成を支援するアプリです。

## Novel Writer

![Novel Writer app icon](../assets/icons/novel-writer.png ':size=40')

アシスタントと共同で小説を執筆するためのアプリケーションです。ユーザーのプロンプトに基づいてストーリーを展開し、一貫性と流れを維持します。AIエージェントは最初に、物語の舞台、登場人物、ジャンル、最終的な文章の量を尋ねます。その後、ユーザーが提供するプロンプトに基づいて、AIエージェントが物語を展開します。


## Mail Composer

![Mail Composer app icon](../assets/icons/mail-composer.png ':size=40')

アシスタントと共同でメールの草稿を作成するためのアプリケーションです。ユーザーの要望や指定に応じて、アシスタントがメールの草稿を作成します。


Mail Composerの対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

このアプリでは、AIエージェントにスピーチのドラフト作成を依頼することができます。ドラフトを一から作成することもできますし、既存のドラフトをテキスト、Word、PDF形式で提出することも可能です。AIエージェントは内容を分析し、修正版や改善案を提案します。必要に応じて、設定したテキスト読み上げプロバイダーがサポートする形式（例：MP3やWAV）で音声ファイルを生成できます。

スピーチの録音を文字起こしすることもできます。メッセージ欄の下の `Image` ボタンから音声ファイルを添付するか（MP3、M4A、WAV、OGG、Opus、FLAC、WebM、AAC）、共有フォルダに置いたファイルの名前を伝えてください。録音の中の発話を先に見つけて区間ごとに文字起こしするため、文字起こしの各行の先頭に、その発話の録音の中での時刻が付きます（例：`[01:02–01:06]`）。50 分までの録音を文字起こしできます。ファイル全体を一度に文字起こしするときの 25 MB の上限はかかりません（添付できるファイルは 2 GB まで）。文字起こしは会話のフォルダ（共有フォルダの `conversations/`）に `transcript.json` として保存され、WebVTT と SRT の字幕ファイルも作られます。時刻付きの文字起こしには、このバージョン用に作られた Python コンテナが必要です。古いコンテナでは時刻なしの文字起こし（25 MB まで）になり、コンテナを作り直すよう注記が付きます。


## Document Generator :id=document-generator

![Document Generator app icon](../assets/icons/document-generator.png ':size=40')

AIを使用してOfficeドキュメントを生成します。Excel、PowerPoint、Word、PDFなど。ファイルは共有フォルダに自動保存されます。

**主な機能：**
- **Excel (.xlsx)**: データテーブル、チャート、数式、複数シート
- **PowerPoint (.pptx)**: ビジュアルレイアウトを備えたプロフェッショナルなスライド
- **Word (.docx)**: 見出し、リスト、表を含むフォーマット済みドキュメント
- **PDF**: 適切なフォーマットのプロフェッショナルなドキュメント

Document Generatorは現在Claudeで利用可能です。
