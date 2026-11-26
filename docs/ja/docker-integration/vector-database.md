# ベクトルデータベース

Monadic Chat には、Knowledge Base とヘルプの文書を意味で検索するためのベクトルデータベースがあります。このページでは、その使われ方を説明します。

## 概要 :id=overview

ベクトルデータベースは、次のことを行います。
- お使いのコンピューターで、テキストをベクトル（埋め込み）に変換します
- ベクトルを、テキストの出どころの情報と一緒に Qdrant コンテナに保存します
- キーワードの一致ではなく、意味の近さでテキストを探します
- Knowledge Base と Monadic Chat Help アプリが使います

埋め込みと検索はローカルで行われ、API キーは要りません。

## 技術的な実装 :id=technical-implementation

### サービスのコンテナ

2 つのコンテナが一緒に働きます。

- **`monadic-chat-qdrant-container`** は、ベクトルデータベース [Qdrant](https://qdrant.tech) を動かします。テキスト、ベクトル、結果の絞り込みやまとめに使う情報を保存します。
- **`monadic-chat-embeddings-container`** は、多言語の埋め込みモデルで、テキストを CPU でベクトルに変換します。このモデルは、英語、日本語をはじめ多くの言語を扱えます。

どちらのコンテナも Monadic Chat と一緒に起動し、設定は要りません。

### テキストの処理の流れ

Knowledge Base にファイルを取り込むときの流れです。

1. **テキストの抽出**：
   - PDF は、Knowledge Base 品質パックをインストールしてあり、動いていれば、Extractor コンテナの [Docling](https://github.com/docling-project/docling)（レイアウトの解析と OCR）で処理されます。そうでなければ、PDF のテキストと表の抽出を Python コンテナで行います。このとき OCR は行わないので、スキャンした画像だけの PDF からはテキストを取り出せません
   - Office のファイル（`.docx`、`.xlsx`、`.pptx`）は Python コンテナで読み込まれます
   - Markdown とソースコードはそのまま読み込まれます
   - テキストは区切りに分けられます。Markdown は見出しで、ソースコードはトップレベルの定義で分けます

2. **埋め込み**：区切りごとに、Embeddings コンテナがベクトルに変換します

3. **保存**：区切りとそのベクトルが、文書の題名、出どころ、種類とともに Qdrant に保存されます

4. **検索**：
   - 質問も、同じモデルでベクトルに変換されます
   - Qdrant が、質問と意味のいちばん近い区切りを返します
   - その区切りが質問と一緒に LLM に渡され、LLM はそれにもとづいて答えます

## 保存されるもの :id=database-schema

- **Knowledge Base**：保存した会話と取り込んだファイル（文書とその区切り）
- **ヘルプのデータ**：Monadic Chat の文書。Monadic Chat Help アプリが使います

## 検索するもの :id=visibility

サイドバーの **書庫** のタブはすべての項目を表示し、Knowledge Base を検索するアプリは、どのアプリで保存した項目もすべて検索します。AI が検索するのは、頼まれたときや明らかに役立つときで、設定の **AI が使える情報源** が許している間だけです。Live Conversation は、アプリの **検索と計算** のスイッチがオンの間だけ検索します。[Knowledge Base](/ja/apps/knowledge-base.md) のページを参照してください。

## Knowledge Base での使い方 :id=use-in-knowledge-base

1. サイドバーの **書庫** のタブで、**この会話を書庫に収める** で今の会話を収める文書として作業画面に置くか、**ファイルを読み込み** をクリックします
2. Monadic Chat が、[上記](#technical-implementation)のとおり、内容を抽出し、分け、埋め込み、保存します
3. Knowledge Base を検索するアプリで、内容について質問します。検索するものは[検索するもの](#visibility)のとおりです
4. Monadic Chat が、まず文書、次に区切りの順で、いちばん関係の深い区切りを探します
5. LLM は、受け取った区切りにもとづいて答えます

取り込みの間、ファイルは `~/monadic/data/library/imports/` に写され、取り込みが終わると写しは消えます。

## Monadic Chat Help での使い方 :id=use-in-monadic-help

Monadic Chat Help アプリは、同じ Qdrant と Embeddings のコンテナでヘルプのデータを検索します。ヘルプのデータは、Monadic Chat情報パネルの **ヘルプデータ** からインストールします。インストールに API キーは要りません。Monadic Chat Help アプリ自体は OpenAI を使うので、このアプリで会話するには OpenAI の API キーが要ります。[ヘルプシステム](../advanced-topics/help-system.md)を参照してください。
