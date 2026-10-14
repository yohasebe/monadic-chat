# ツールグループ

## 概要

ツールグループは、いくつものアプリで共有する、関連するツールのまとまりです。アプリは `import_shared_tools` でグループを取り込み、アプリの説明に、使っているグループが表示されます。

## ツールグループのバッジ

アプリの説明の欄に、ツールグループがバッジで表示されます。行は最大で 3 つです。

- **Tools (Always)**：最初からツールがモデルに送られるグループ
- **Tools (Conditional)**：モデルが `request_tool` で求めるまで隠れているグループ
- **Capabilities**：Web 検索や Knowledge Base など、アプリの機能

バッジには、グループのアイコンと名前が表示されます。バッジにポインターを重ねると、説明とツールの数が表示されます。条件を満たしていない `conditional` のグループは表示されません。

## 利用可能なツールグループ

下のアプリの一覧は、それぞれのグループを取り込んでいる組み込みのアプリです。

### 条件のないグループ

#### Jupyter Operations（12 ツール）
- Jupyter のノートブックを作り、管理する
- ノートブックにセルを加える
- JupyterLab でコードを実行する
- ノートブックの一覧と内容を取得する

**使っているアプリ**：Jupyter Notebook

#### Python Execution（4 ツール）
- Python コンテナで Python のコードを実行する
- Python の環境とパッケージを確かめる
- Python のライブラリをインストールする

**使っているアプリ**：Code Interpreter、Jupyter Notebook、Math Tutor、Research Assistant

#### File Operations（3 ツール）
- 共有フォルダのファイルを読む
- 共有フォルダのファイルに書き込む・追記する
- 共有フォルダのファイルの一覧を得る

**使っているアプリ**：すべてのアプリに自動で加わります。

#### File Reading（3 ツール）
- 共有フォルダのテキストファイルを読む
- PDF のファイルからテキストを取り出す
- Office の文書（Word、Excel、PowerPoint）からテキストを取り出す

**使っているアプリ**：Code Interpreter、Jupyter Notebook、Math Tutor、Research Assistant

#### Planning（1 ツール）
- いくつもの手順がある作業の計画を示す
- 作業を始める前に、計画を利用者に見せて承認を得る

**使っているアプリ**：ツールを使うアプリの多く。たとえば Code Interpreter、Coding Assistant、Research Assistant、Jupyter Notebook、Math Tutor、AutoForge（OpenAI、Grok）、Mermaid Grapher、DrawIO Grapher、Web Insight

#### Parallel Python Execution（1 ツール）
- 互いに独立した 2〜5 個の Python のコードを並行して実行する
- それぞれのコードは別のプロセスで動き、結果はまとめて集められる
- 実行中は、進み具合が一時的なカードに表示される

**使っているアプリ**：Code Interpreter

#### Parallel Dispatch（1 ツール）
- 互いに独立した 2〜5 個の小さな作業を、別々の API の呼び出しで並行して実行する
- それぞれのサブエージェントはテキストだけの呼び出しで動き、結果は集められてまとめられる
- Web Search のスイッチがオンなら、サブエージェントも Web を検索できる。検索にはプロバイダー自身の検索を使い、それがないプロバイダーでは Tavily API を使う。[プロバイダー機能の表](../basic-usage/basic-apps.md#provider-capabilities)を参照
- 実行中は、進み具合が一時的なカードに表示される

**使っているアプリ**：Research Assistant

#### Verification（1 ツール）
- 利用者に示す前に、作業を確かめた結果を記録する
- 状態：passed、issues found、fixed
- 状態が passed か fixed になるか、3 回試すと、ツールの繰り返しが止まる
- 実行中は、状態が一時的なカードに表示される

**使っているアプリ**：Code Interpreter、Jupyter Notebook、Mermaid Grapher、AutoForge（OpenAI、Grok）

#### App Creation（3 ツール）
- Monadic Chat のアプリの一覧を得る
- アプリの詳しい情報を得る
- アプリのひな形のファイルを作る

**使っているアプリ**：組み込みのアプリにはありません。独自のアプリで `import_shared_tools` か `reachable_skills` を使えば使えます

#### Session Context（4 ツール）
- 会話の文脈（話題、人物、メモ）を取得・更新・消去する
- 文脈から特定の項目を取り除く
- 文脈はサイドバーのパネルに表示される

**使っているアプリ**：Chat Plus

### 条件のあるグループ

#### Web Automation（16 ツール）
**必要なもの**：Selenium と Python のコンテナ

- Web ページを、画面の大きさのスクリーンショットとして撮る（端末のプリセットあり）
- noVNC で見られる、操作できるブラウザーのセッションを動かす
- 操作できるブラウザーで、移動、クリック、入力、スクロール、選択、キーの入力をする
- ページの構造を調べ、候補の要素に印を付ける

**使っているアプリ**：Web Insight、AutoForge、Research Assistant（OpenAI、Claude、Gemini、Grok）

Selenium のコンテナは Monadic Chat とともに起動します。グループが表示されないときは、起動が終わるまで待ってください。Selenium のイメージがないときは、**Actions → Build All** でダウンロードします。

#### Video Analysis（1 ツール）
**必要なもの**：OpenAI、Anthropic、Gemini、xAI のどれかで動くアプリと、そのプロバイダーの API キー

- マルチモーダルのモデルで動画の内容を分析する
- フレームから動画を説明する
- フレームはアプリ自身のプロバイダーにだけ送られる。そのプロバイダーに音声認識があれば（OpenAI、Gemini、xAI）、音声も文字に起こされる。なければ、音声は文字に起こしていないと説明に書かれる

**使っているアプリ**：Video Describer

#### Web Search（4 ツール）
**必要なもの**：`TAVILY_API_KEY`

- Tavily で Web を検索し、ページを取得する（引用付き）
- URL の内容を取得し、共有フォルダに保存する

このグループの検索のツールは、Tavily を通して結果を返します。プロバイダー自身の Web 検索は、Web Search のスイッチでオンにする別の機能で、このグループがなくても使えます。[プロバイダー機能の表](../basic-usage/basic-apps.md#provider-capabilities)を参照してください。`TAVILY_API_KEY` がないときは、このグループの検索のツールは結果を返しません。

**使っているアプリ**：Research Assistant、Mermaid Grapher、Wikipedia

#### Audio Transcription（1 ツール）
**必要なもの**：OpenAI、Gemini、xAI のどれかで動くアプリと、そのプロバイダーの API キー

- 音声認識で音声のファイルを文字に起こす
- 音声はアプリ自身のプロバイダーにだけ送られる。ほかのプロバイダーのアプリには、このツールはない

**使っているアプリ**：Speech Draft Helper

#### Image Analysis（1 ツール）
**必要なもの**：OpenAI、Anthropic、Gemini、xAI、Mistral、Cohere、DeepSeek のどれかで動くアプリと、そのプロバイダーの API キー

- モデルの画像を読む能力で、画像のファイルの内容を説明する
- 画像はアプリ自身のプロバイダーにだけ送られる

**使っているアプリ**：Code Interpreter、Research Assistant、Speech Draft Helper

#### Library Search（1 ツール）
**必要なもの**：Knowledge Base（Qdrant と embeddings のコンテナ）

- 問い合わせに関係する部分を Knowledge Base から探す
- もとの会話や文書へのリンクの付いた引用とともに、該当する部分を返す

**使っているアプリ**：Knowledge Base を検索できるアプリに加わります。セッションで Knowledge Base の検索のスイッチがオンのときに使われます

プロバイダーにない能力（画像、動画、音声の入力）が要るグループは、そのプロバイダーのアプリには加わりません。

## ツールの利用可否について

### 一部のツールが利用できない理由

1. **コンテナ**：Docker のコンテナ（Selenium、Python）が要るツールがあります
2. **API キー**：特定の API キーが要るツールがあります
3. **プロバイダーの能力**：画像、動画、音声の入力が要るツールがあります

### エラーメッセージ

ツールを実行できないときは、エラーのメッセージに、何が足りないか（たとえば "Selenium container is not running"）と、どう直すか（たとえば、コンテナの起動を待つ、Selenium のイメージがなければ **Actions → Build All** を実行する）が書かれます。

## ツールグループを使ったアプリの作成

MDSL で独自のアプリを作るときは、ツールを 1 つずつ定義する代わりに、ツールグループを取り込めます。[Monadic DSL](monadic_dsl.md) を参照してください。

### 例

```ruby
app "MyCustomAppOpenAI" do
  llm do
    provider "openai"
    model "<model-id>"
  end

  # Import Python execution tools
  import_shared_tools :python_execution, visibility: "always"

  # Import web automation tools (hidden until the model asks for them)
  import_shared_tools :web_automation, visibility: "conditional"
end
```

visibility の既定は `"conditional"` です。

## 動的スキル（reachable_skills）

アプリは、使うかもしれないツールをすべて宣言する必要はありません。`reachable_skills` で、会話の途中で使えるようになるツールグループを宣言できます。モデルが必要とするまで、ツールは隠れています。

しくみ：

1. 隠れているグループは、短いメニュー（グループごとの名前と 1 行の説明）としてモデルに示されます。
2. モデルはグループが必要になると、名前で求めます（`request_tool("web_search_tools")`）。
3. グループ全体が使えるようになり、そのツールは会話の終わりまで使えます。

```ruby
app "MyAssistantOpenAI" do
  llm do
    provider "openai"
    model "<model-id>"
  end

  # Groups the app can reach for when the conversation calls for them.
  reachable_skills :web_search_tools, :image_analysis

  # Or reach for the curated pool of read-only safe groups in one line:
  # reachable_skills :safe
end
```

`reachable_skills :group_a, :group_b` は、それぞれのグループを `import_shared_tools :group_a, visibility: "conditional"` で取り込むのと同じです。`reachable_skills :safe` は、読み取り専用のグループに展開されます：Web Search、File Reading、Image Analysis、Video Analysis、Audio Transcription、Session Context、Verification、Planning。

使えるようになったスキルは、セッションを書き出すと保存され、読み込むと元に戻るので、保存した会話は同じツールで続けられます。

## トラブルシューティング

### ツールグループが利用できないままの場合

必要なコンテナが起動した後も、ツールグループが使えないままのとき：

1. **Web の画面を再読み込みする**：使えるかどうかは、アプリの一覧を作るときに確かめられます
2. **Monadic Chat を再起動する**：Stop してから Start します
3. **コンテナを確かめる**：`docker ps` を実行するか、コンソールのパネルのメッセージを読みます
4. **ログを確かめる**：コンテナのログに、起動しなかった理由が出ていることがあります

### ツールが期待通りに動作しない場合

ツールは使えるのに、うまく動かないとき：

1. **共有フォルダを確かめる**：ファイルを読めるか確かめます
2. **API キーを確かめる**：有効で、残高があるか確かめます
3. **コンテナのログを確かめる**：コンテナの出力にエラーがないか見ます
4. **Monadic Chat を再起動する**

## 関連ドキュメント

- [Monadic DSL](monadic_dsl.md) - 独自のアプリの作成
- [Docker 統合](../docker-integration/basic-architecture.md) - コンテナの管理
- [共有フォルダ](../docker-integration/shared-folder.md) - ファイルの操作
