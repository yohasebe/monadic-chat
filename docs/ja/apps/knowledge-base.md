# Knowledge Base

チャットセッションの保存とドキュメントのインポートを、どのアプリからも検索できる単一のライブラリに集約します。

プロジェクト全体で共有される、会話とドキュメントの統合ライブラリです。Knowledge Base はすべての Monadic Chat アプリから参照可能なため、ここに保存した内容はどのチャットセッションからも検索・引用できます。

Knowledge Base は従来の PDF Navigator と Content Reader を置き換えるサブシステムです。会話のトランスクリプト、PDF、Office ファイル、Markdown、ソースコードを単一のインターフェースで扱えるようにまとめています。

?> Knowledge Base はアプリ単位の [PDF Database パネル](../basic-usage/pdf_storage.md)（`pdf_vector_storage` を宣言したアプリ＝現在は Chat Plus と Research Assistant 向けのアプリスコープ PDF ストレージ）とは別の機能です。一方に取り込んだ内容がもう一方に現れることはありません。

**コンテンツの追加方法は 2 通り:**

1. **現在のチャットセッションを保存** — サイドバーの **Save** ボタンで、進行中の会話 (メッセージ + 参加者 + メタデータ) を Knowledge Base にシリアライズします。
2. **ファイルをインポート** — Knowledge Base Browser を開き、**Import file** ボタンから対応形式のファイルをアップロードします。ファイルは抽出・チャンク分割・埋め込みされ、検索・閲覧・リネーム可能な 1 件の会話エントリとして保存されます。

**インポート対応フォーマット:**

| フォーマット | 拡張子 | 備考 |
|---|---|---|
| Markdown | `.md`, `.markdown`, `.mdx` | YAML フロントマターはメタデータに昇格、ATX 見出しでセクション分割 |
| ソースコード | `.rb`, `.py`, `.js` / `.ts`, `.go`, `.java`, `.kt`, `.swift`, `.rs`, `.c` / `.cpp`, `.cs`, `.php`, `.sh`, `.sql` ほか | トップレベルの `def`/`class`/`func` などをチャンク境界とみなす。プログラミング言語は topic に記録 |
| PDF | `.pdf` | テキストと表を抽出して Markdown 化。Knowledge Base Quality Pack がインストールされている場合はレイアウト解析 + OCR 付きの抽出になる。PDF メタデータの title が会話タイトルになる |
| Office | `.docx`, `.xlsx`, `.pptx` | Word の段落、Excel のシート、PowerPoint のスライド単位でチャンク化。Browse モーダルではフォーマット別アイコン (Word / Excel / PowerPoint) で表示 |

**スコープ (scope) モデル:**

各エントリは特定のアプリ＋プロバイダ (例: `Chat (OpenAI)`) か `Global` のいずれかにスコープされます。アプリ単位スコープのエントリは同一のアプリ＋プロバイダの組み合わせからのみ検索対象になります — `Chat (OpenAI)` で保存したエントリを `Chat (Claude)` から見ることはできません。`Global` のエントリは `library_search` ツール経由でどのアプリからでも検索可能です。Browse テーブルの rotate アイコン、または Conversation Viewer の **Make Global / Make app-only** ボタンで切り替えできます。

**その他の機能:**

- **再保存は既存エントリを上書き** — 同じセッションを 2 回目以降保存すると、新規作成ではなく既存エントリを更新します。再保存時はモーダルが「Update Conversation in Knowledge Base」モードに切り替わり、「Update」ボタンと警告バナーが表示されます。Reset / アプリ切替 / Browse からの削除でこの紐付けは解除されます。
- **AI によるタイトル提案** — 初回保存時、タイトル欄は現在のプロバイダーの LLM が会話の最初の数ターンから簡潔なタイトルを生成して自動入力します。これはデフォルトとしての提案であり、自由に上書きできます。提案結果はキャッシュされるため、保存をキャンセルして再度開いても再リクエストは発生しません。
- **リネーム** — Conversation Viewer を開き、タイトル横の鉛筆アイコンをクリック、編集して保存。Browse テーブルも即座に反映します。
- **インベントリと統計** — サイドバーには直近の保存とトータル件数。Browse モーダルでは検索・スコープフィルター・ソートが可能。
- **Conversation Viewer** — 行をクリックすると全メッセージの逐語表示。システムプロンプトは `<details>` で折り畳み済みで開きます。
- **RAG オプトイン (セッション単位)** — 任意のチャットセッションで **Use Knowledge Base for retrieval** トグルを ON にすると、LLM が応答中に `library_search` を呼び出せます。検索カスケードは現在アクティブなアプリのスコープフィルター (`scope_app IN [current_app, "Global"]`) を適用します。デフォルト OFF、最初のメッセージ送信でセッション中はロックされます。トグルの状態はセッションを跨いで永続化されるので、毎回切り替える必要はありません。
- **Privacy Filter との互換性** — Privacy Filter が有効なセッションでは、`library_search` が返すスニペットも同じ Privacy Pipeline でマスクされてから LLM に渡されます。Knowledge Base に平文で保存された PII が retrieval 経由で漏出しません。
- **Knowledge Base アクセスバッジ** — セッションが実際に Library を参照する状態のとき、会話ヘッダーに緑の「Knowledge Base」バッジが表示されます。retrieval トグルが ON のとき、および Knowledge Base アプリ自体（専用ツールで常にフルアクセス）が対象です。

?> Knowledge Base はローカル埋め込み (`multilingual-e5-base`) と Qdrant ベクトルストアを使用します — インポートにも検索にも外部 API キーは不要です。抽出・チャンク化・ストレージの内部詳細は[ベクトルデータベース](../docker-integration/vector-database.md)のドキュメントを参照してください。
