# 語学学習アプリ

語学の練習・翻訳・通訳のためのアプリです。会話の練習のために、音声合成と音声入力を使えます。

## Language Practice

![Language Practice app icon](../assets/icons/language-practice.png ':size=40')

アシスタントから話しかけてくる会話で、語学を練習するアプリです。アシスタントの応答は読み上げられます。声で答えるときは、右矢印キーを押すか音声入力のボタンをクリックすると話し始められ、もう一度ボタンをクリックすると終わります。話した内容はそのまま送信されます。

Language Practice の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。音声の設定は [Speech パネル](../basic-usage/web-interface.md#speech-settings-panel)を参照してください。


## Language Practice Plus

![Language Practice Plus app icon](../assets/icons/language-practice-plus.png ':size=40')

Language Practice と同じように使え、言葉の使い方についての助言が加わります。助言は、[作業画面](../basic-usage/web-interface.md#work-screen)に **Practice notes** のページとしてまとめられます。


## Translate

![Translate app icon](../assets/icons/translate.png ':size=40')

テキストを別の言語に翻訳するアプリです。アシスタントは、まず翻訳元と翻訳先の言語を尋ねます。語句の訳し方を指定したいときは、語句のすぐ後に、括弧に入れて訳語を書きます（`原文の語句(希望する訳語)`）。この組はセッションの語彙として保持され、その後の翻訳で使われます。数文を超える長い訳は会話の横の[作業画面](../basic-usage/web-interface.md#work-screen)に表示され、いちばん新しい版が表示されます（前の版は **版** で一覧できます）。短い訳は会話の中で答えます。言語と語彙は、作業画面にも 1 つのページとして表示されます。会話のフォルダの `notes/translation-notes.md` です。ターンがそれを変えたときや、ターンを削除したときに作り直されます。語彙の項目を足したターンを削除すると、その項目だけが元に戻ります。

Translate の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。それぞれの言語をどれだけうまく訳せるかは、プロバイダーによって違います。


## Voice Interpreter

![Voice Interpreter app icon](../assets/icons/voice-chat.png ':size=40')

話した内容を別の言語に翻訳し、その訳を音声で聞けるアプリです。アシスタントは、まず翻訳先の言語を尋ね、その後は話した内容を翻訳して、訳だけを読み上げます。言語と翻訳したフレーズは、[作業画面](../basic-usage/web-interface.md#work-screen)に **Interpreter notes** のページとしてまとめられます。

Voice Interpreter の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。音声の設定は [Speech パネル](../basic-usage/web-interface.md#speech-settings-panel)を参照してください。
