# 文章・ドキュメント作成アプリ

小説・メール・スピーチの原稿から Office の文書まで、文章を書くのを手伝うアプリです。

## Novel Writer

![Novel Writer app icon](../assets/icons/novel-writer.png ':size=40')

アシスタントと一緒に小説を書くアプリです。アシスタントは最初に、ジャンル、物語の言語、おおよその長さ、考えている登場人物や舞台を尋ねます。その後は、指示に沿って物語を 1 節ずつ書き、次の展開の選択肢を示します。物語は会話の横の[作業画面](../basic-usage/web-interface.md#work-screen)に、すべての節を順に区切り付きでつないだ 1 つの文章として表示されます。会話にはどの節を書いたかが書かれ、返答の下の行を押すと、その節の位置で物語が開きます。節の書き直しを頼むと新しい版がその位置に入り、そのターンを削除すると前の版に戻ります。ターンごとの節は会話のフォルダに別々のファイルとして残り、物語の全体はそのフォルダの `documents/<題名>.md` です。ターンを削除すると、そのターンが変えた物語の設定や登場人物は元に戻ります。書いた量は、物語そのものから数えます。物語のメモ（筋、あらすじ、登場人物、進み具合）は、作業画面に別のページとして表示されます。会話のフォルダの `notes/story-notes.md` です。ターンがメモを変えたときや、ターンを削除したときに、会話から作り直されます。各部分には、それを最後に変えたターンが示されます。


## Mail Composer

![Mail Composer app icon](../assets/icons/mail-composer.png ':size=40')

アシスタントと一緒にメールの下書きを作るアプリです。アシスタントは、まずどのようなメールかを尋ね、その後は要望に沿って下書きを作ります。下書きは会話の横の[作業画面](../basic-usage/web-interface.md#work-screen)に表示され、いちばん新しい版が表示されます。前の版はそれを書いたターンとともに残り（**版** で一覧できます）、直したターンを削除すると、その前の版に戻ります。会話には何を変えたかが書かれます。Mail Composer では Web 検索を使えます。


Mail Composer の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

アシスタントと一緒にスピーチの原稿を作るアプリです。テーマを伝えて書いてもらうことも、下書き（テキスト、Word、PDF）を渡して改善してもらうこともできます。スピーチは音声ファイルとして会話のフォルダに保存でき、チャットの横の作業画面で再生できます。形式は、OpenAI と ElevenLabs の声では MP3、Gemini の声では API が返す形式（ふつうは WAV）です。

スピーチの録音を文字起こしすることもできます。メッセージ欄の下の添付のボタン（モデルによって `Attach file` または `Image`）から音声ファイルを添付するか（MP3、M4A、WAV、OGG、Opus、FLAC、WebM、AAC）、共有フォルダに置いたファイルの名前を伝えてください。録音の中の発話を先に見つけて区間ごとに文字起こしするため、文字起こしの各行の先頭に、その発話の録音の中での時刻が付きます（例：`[01:02–01:06]`）。50 分までの録音を文字起こしできます。ファイル全体を一度に文字起こしするときの 25 MB の上限はかかりません（添付できるファイルは 2 GB まで）。文字起こしは会話のフォルダ（共有フォルダの `conversations/`）に `transcript.json` として保存され、WebVTT と SRT の字幕ファイルも作られます。時刻付きの文字起こしには、最新の Python コンテナが必要です。コンテナがアプリより古いときは、時刻なしの文字起こし（25 MB まで）になり、**Actions → Build Python Container** でコンテナを作り直すよう注記が付きます。


## Document Generator :id=document-generator

![Document Generator app icon](../assets/icons/document-generator.png ':size=40')

Excel のスプレッドシート、PowerPoint のプレゼンテーション、Word の文書、PDF を作るアプリです。ファイルは会話のフォルダに保存され、会話にはそのパスが 1 行で示されます。PDF は会話の横の[作業画面](../basic-usage/web-interface.md#work-screen)にも表示されます。ほかのファイルは[ファイルのタブ](../basic-usage/web-interface.md#shared-folder-panel)か共有フォルダから開きます。

**主な機能：**
- **Excel (.xlsx)**：データの表、グラフ、数式、複数のシート
- **PowerPoint (.pptx)**：レイアウトの付いたスライド
- **Word (.docx)**：見出し、箇条書き、表のある文書
- **PDF**：書式の整った文書

Document Generator では Web 検索を使えます。Claude で使え、Anthropic の API キーが必要です。
