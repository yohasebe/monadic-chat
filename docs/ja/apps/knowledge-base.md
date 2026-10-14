# Knowledge Base

チャットのセッションを保存し、文書を取り込んで、まとめて検索できるライブラリです。

Knowledge Base には、会話と文書（会話の記録、PDF、Office のファイル、Markdown、ソースコード）を入れられます。Knowledge Base アプリはそのすべてを検索し、ほかのアプリは下の「範囲の決まり」のとおりに検索できます。

?> Knowledge Base は、Chat Plus と Research Assistant の OpenAI 版で使う [PDF Database](../basic-usage/pdf_storage.md) とは別のものです。一方に取り込んだ内容は、もう一方には表示されません。

**内容を加える 2 つの方法：**

1. **今のチャットのセッションを保存する**：サイドバーの Knowledge Base パネルの **Save** ボタンで、今の会話を Knowledge Base に保存します。
2. **ファイルを取り込む**：Knowledge Base のブラウザー（**Browse**）を開き、**Import file** をクリックして、下の形式のファイルをアップロードします。ファイルからテキストが取り出され、節に分けられ、検索・表示・名前の変更ができる 1 つの項目として保存されます。

**取り込める形式：**

| 形式 | 拡張子 |
|---|---|
| Markdown | `.md`、`.markdown`、`.mdx` |
| ソースコード | `.rb`、`.py`、`.js` / `.ts`、`.go`、`.java`、`.kt`、`.swift`、`.rs`、`.c` / `.cpp`、`.cs`、`.php`、`.sh`、`.sql` など |
| PDF | `.pdf` |
| Office | `.docx`、`.xlsx`、`.pptx` |

PDF からはテキストと表が取り出されます。Knowledge Base Quality Pack を入れているときは、レイアウトの解析と OCR が使われます。入れていないときは、画像だけの PDF からはテキストが取り出されません。

Privacy Filter を使うアプリ（Translate、Mail Composer など）は Knowledge Base に保存も検索もしません。ほかにも、保存や検索をしないアプリがあります。それらのアプリでは、Save ボタンと検索のスイッチは使えません。

**範囲の決まり：**

それぞれの項目は、保存したときのアプリとプロバイダー（例：`Chat (OpenAI)`）か、`Global` のどちらかに属します。アプリが Knowledge Base を検索するとき、アプリだけの項目は、同じアプリとプロバイダーからしか見つかりません。`Chat (OpenAI)` からは `Chat (Claude)` で保存した項目は見つからず、その逆も同じです。`Global` の項目は、Knowledge Base を検索するすべてのアプリから見つかります。Browse の表の回転のアイコン、または Conversation Viewer の **Make Global** / **Make app-only** で切り替えます。

**そのほかの機能：**

- **もう一度保存すると項目が更新される**：同じチャットのセッションをもう一度保存すると、新しい項目は作られず、前の項目が更新されます。このときダイアログは「Update Conversation in Knowledge Base」となり、**Update** ボタンと注意書きが表示されます。セッションと項目の結び付きは、Reset、アプリの切り替え、Browse での項目の削除で切れます。
- **タイトルの提案**：会話を初めて保存するとき、今のプロバイダーのモデルが会話にもとづいてタイトルの欄を埋めます。自由に書き換えられます。提案は保持されるので、ダイアログを閉じて開き直しても、モデルにもう一度尋ねることはありません。
- **名前の変更**：Conversation Viewer を開き、タイトルの横の鉛筆のアイコンをクリックして編集し、保存します。
- **最近の保存と件数**：サイドバーに最近の保存と全体の件数が表示されます。Browse の表では、検索、範囲での絞り込み、並べ替えができます。
- **Conversation Viewer**：行をクリックすると、その項目のすべてのメッセージが表示されます。システムプロンプトは折りたたまれています。
- **ほかのアプリでの検索**：Knowledge Base パネルの **Use Knowledge Base for retrieval (this session)** をオンにすると、モデルが回答の途中で Knowledge Base を検索できます。見つかるのは、今のアプリの項目と `Global` の項目です。このスイッチは既定でオフで、最後の選択が記憶されます。Live Conversation では、代わりにアプリの **Tools** のスイッチを使います。
- **Knowledge Base のバッジ**：セッションが Knowledge Base を読める間、会話の見出しに緑の「Knowledge Base」バッジが表示されます。検索のスイッチがオンのときと、Knowledge Base アプリでは常に表示されます。

## Knowledge Base アプリ

Knowledge Base アプリは、Knowledge Base そのものを扱うためのチャットです。範囲にかかわらず、すべての項目を扱えます。次のことを頼めます。

- すべての項目の検索、項目の一覧、1 つの項目の詳細の表示
- 項目の数（全体と範囲ごと）
- 項目の範囲を `Global`、または `Chat (OpenAI)` のようなアプリとプロバイダーに変えること
- テキストや JSON で貼り付けた会話の取り込み（ChatML、Anthropic Messages、Gemini Contents、Monadic Chat の書き出し、話し手のラベル付きのテキスト）。アプリを指定しなければ、項目は `Global` になります
- 項目の削除（先に確認を求めます）

対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。

?> Knowledge Base は、テキストをお使いのコンピューターの上でベクトルに変換し、Qdrant に保存します。取り込みと検索に API キーは要りません。[ベクトルデータベース](../docker-integration/vector-database.md)を参照してください。
