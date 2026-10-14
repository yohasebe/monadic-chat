# 共有フォルダ

Monadic Chat を最初に起動すると、`~/monadic/data` ディレクトリが作られます。これが、Monadic Chat の Docker コンテナとファイルを共有するための共有フォルダです。

Monadic Chat のコンソールの `Shared Folder` ボタン（または **Open → Open Shared Folder**）で、共有フォルダが OS のファイルマネージャーで開きます。

<!-- SCREENSHOT: Monadic Chatコンソール - 上部にStart/Stopボタン、中央にログ表示エリア、下部にShared Folderボタンが配置されている様子 -->

このフォルダに置いたファイルは、Monadic Chat の Docker コンテナから使えます。共有フォルダのパスは、お使いのコンピューターでは `~/monadic/data`、各 Docker コンテナの中では `/monadic/data` です。

コードを実行できるアプリ（Code Interpreter など）では、共有フォルダのファイルを読み込めます。共有フォルダのいちばん上にあるファイルは名前だけで指定できます。サブフォルダの中のファイルは、共有フォルダからの相対パスで指定します。

AI エージェントが（function calling などで）処理を行う途中で、中間のファイルが共有フォルダに保存されることがあります。ときどき確認して、要らないファイルを消してください。

JupyterLab も `/monadic/data` で起動するので、JupyterLab からも共有フォルダのファイルを使えます。[JupyterLab との連携](./jupyterlab.md)を参照してください。

## `${SHARED}` 変数

会話の中では、共有フォルダを `${SHARED}` で表せます。アシスタントは `${SHARED}` を共有フォルダと理解するので、フルパスを入力せずにファイルの読み書きを頼めます。例：*「要約を `${SHARED}/notes.md` に保存して」*、*「`${SHARED}/data.csv` を読んでグラフにして」*。アシスタントがツールの呼び出しで `${SHARED}` を使うと、Monadic Chat がそれを共有フォルダの実際の場所に置き換えます。

どのアプリでも、共有フォルダのテキストファイルを読み書きできます。アシスタントは、どのアプリでも `read_file_from_shared_folder`・`write_file_to_shared_folder`・`list_files_in_shared_folder` を使えます（Live Conversation には、代わりに専用のツールがあります）。これで、どのアプリでもアシスタントとファイルをやり取りできます。たとえば、翻訳する元の文章を渡す、文字起こしを保存する、前のターンで作ったファイルを参照する、といったことです。これらのツールは、`apps`、`helpers`、`scripts`、`services` の各フォルダには書き込みません。

アシスタントの応答では、`${SHARED}` はクリックできるトークンとして表示されます。マウスを重ねるとパスが表示されます。Monadic Chat のウィンドウではクリックするとその場所が OS のファイルマネージャーで開き、外部のブラウザーではクリックするとパスがコピーされます。

> ファイルの読み書きには、tool calling に対応したモデルが必要です。対応していないモデルでも会話はできますが、ファイルの読み書きはできません。

## その他のインターフェイス変数

`${SHARED}` のほかにも、いくつかの変数がすべての会話で使えます。それぞれ、今のセッションについての情報に置き換わります。

| 変数 | 置き換わる値 |
| --- | --- |
| `${SHARED}` | 共有フォルダ（お使いのコンピューターでは `~/monadic/data`）。 |
| `${TODAY}` | 今日の日付（ISO 8601 形式、`YYYY-MM-DD`）。 |
| `${MODEL}` | 今その会話に答えている AI モデル。 |
| `${APP}` | 今のアプリの表示名。 |
| `${LANG}` | その会話で返答する言語（会話の言語が Automatic のときは、画面の言語）。 |

たとえば、`${TODAY}` は `2026-05-31` のような日付に、`${MODEL}` は今の応答を生成しているモデルの名前に置き換わります。

`${SHARED}` と同じく、これらの変数も既定ですべてのアプリで使えます。

### アプリ固有の変数

いくつかの変数は、すべての会話ではなく、意味のあるアプリだけで使えます。

| 変数 | 使えるアプリ | 置き換わる値 |
| --- | --- | --- |
| `${LAST_GENERATED_IMAGE}` | Image Generator | セッションの中でアシスタントが最後に生成した画像のファイル名。 |
| `${LAST_UPLOADED_IMAGE}` | Image Generator | 会話の中で利用者が最後にアップロードした画像のファイル名。 |
| `${NOTEBOOK}` | Jupyter Notebook | 今使っているノートブックのファイル名。 |

これらは、対応するアプリを使っているときだけ Available Variables のパネルに表示されます。すべての会話で使える変数と同じく、ツールの呼び出しと表示される文の中で値に置き換わります。値がまだ無いうち（画像やノートブックがまだ無いとき）は、書かれたトークンのまま残ります。

## 変数の表示のされ方

インターフェイス変数は 2 つの種類に分かれ、アシスタントの応答の中での表示が違います。

- **パスを表す変数は装飾されます。** `${SHARED}` は応答の中で `${SHARED}` という記号のまま表示され、マウスを重ねるとパスが表示されます（上記）。
- **値を表す変数は展開されます。** `${TODAY}`、`${MODEL}`、`${APP}`、`${LANG}` とアプリ固有の変数は、その場で値に置き換わります。たとえば「今日は `${TODAY}` です」と書かれた文は、「今日は 2026-05-31 です」と表示されます。

ツールの呼び出しやファイルのパスの中では、表示される文の中だけでなく、アシスタントが使うときにすべてのインターフェイス変数が実際の値に置き換わります。変数は組み合わせることもできます。*「`${SHARED}/report_${TODAY}.txt` にレポートを書いて」* と頼むと、日付が入った名前（`report_2026-05-31.txt` など）で共有フォルダにファイルが書き込まれます。

## Available Variables パネル

右側の Monadic Chat Info パネルには、折りたためる Available Variables の欄があります。ここには、今のアプリで使えるインターフェイス変数が、それぞれの短い説明と今の値とともに並びます。今の会話で何が使えるかを、ひと目で確かめられます。

この欄は、既定では折りたたまれています。開くと、変数と値の一覧が表示されます。

## 共有フォルダに保存されるファイル

### 基本アプリが作るファイル

- **Code Interpreter**：コードの実行中に作られる中間のファイルや結果のファイル（CSV、テキスト、画像など）
- **Image Generator**：生成した画像（PNG。OpenAI では JPEG や WebP でも保存できます）
- **Video Generator**：生成した動画（MP4）
- **Jupyter Notebook**：ノートブック（`.ipynb`）
- **Video Describer**：動画から取り出したフレーム（PNG、`frames_<timestamp>` フォルダの中）と音声（MP3）
- **Speech Draft Helper**：読み上げの音声（MP3。Gemini では API が返す形式で、ふつうは WAV）
- **Syntax Tree**：樹形図（SVG）
- **Concept Visualizer**：概念図（SVG と PNG）
- **Mermaid Grapher**：図のプレビュー（PNG）
- **DrawIO Grapher**：図のファイル（`.drawio`）とプレビュー（PNG）
- **Web Insight**：Web ページのスクリーンショット（PNG）

ほとんどのファイルは、タイムスタンプや識別子を含む名前で、共有フォルダのいちばん上に保存されます。要らなくなったファイルは、ときどき消してください。


## Monadic Chat のディレクトリ構造

Monadic Chat は起動するとき、次のフォルダが無ければ作ります。

```text
~/monadic/
├── config/         # 設定ファイル（env、rbsetup.sh、pysetup.sh）
├── data/           # 共有フォルダ（コンテナからは /monadic/data）
│   ├── apps/       # 自作のアプリ
│   ├── helpers/    # ヘルパーの Ruby ファイル
│   ├── scripts/    # Python コンテナで使う実行可能なスクリプト
│   └── services/   # 自作の Docker コンテナの定義
├── log/            # ログファイル（server.log、docker_build.log など）
└── state/          # Monadic Chat 自身の記録（編集しないでください）
```


`data` フォルダが共有フォルダで、Ruby、Python、Selenium、Extractor の各コンテナにマウントされます。その中の `apps`、`helpers`、`services` フォルダは、コンテナの中では読み取り専用です。これらのサブフォルダには、Monadic Chat に自分で加えるものを置きます。追加のアプリの作り方は、[追加アプリの開発](../advanced-topics/develop_apps.md)を参照してください。

`apps`

基本アプリのほかに加えるアプリを置くフォルダです。各アプリは、`apps` の中に自分のサブフォルダを作って置きます。

`helpers`

アプリで使う関数（メソッド）を書いたヘルパーの Ruby ファイルを置くフォルダです。ヘルパーのファイルはアプリのレシピファイルより前に読み込まれるので、いくつものアプリで共通のコードをまとめて使い回せます。

`services`

自作の Docker コンテナの定義を置くフォルダです。[Docker コンテナの追加](../advanced-topics/adding-containers.md)を参照してください。

`scripts`

実行できるスクリプト（シェルスクリプト、Python スクリプトなど）を置くフォルダです。Python コンテナで実行されます。ここに置いたスクリプトには自動で実行権限が付き、コンテナの PATH に入るので、フルパスを書かずに名前だけで実行できます。このフォルダは PATH の最後に置かれるので、システムのコマンドと同じ名前（`python3`、`bash` など）のスクリプトでそのコマンドが置き換わることはありません。スクリプトには固有の名前を付けてください。Ruby 側（`container: "ruby"`）では実行されません。Ruby 側では Monadic Chat に付属するスクリプトだけを実行します。

### 自作のスクリプトの仕組み

1. **置く場所**：お使いのコンピューターの `~/monadic/data/scripts` に置きます
2. **コンテナでのパス**：コンテナの中では `/monadic/data/scripts` にあります
3. **実行権限**：コマンドを実行する前に、毎回スクリプトに実行権限が付きます
4. **名前で実行**：名前だけで呼び出せます（`/monadic/data/scripts/my_script.py` ではなく `my_script.py`）
5. **使えるコンテナ**：Python コンテナで動きます（Ruby 側では動きません）

### アプリでの使用例

```ruby
# 自作の Python スクリプトの実行
send_command(
  command: "analyze_data.py input.csv output.json",
  container: "python"
)

# 別の自作 Python スクリプトの実行
send_command(
  command: "process_text.py document.txt",
  container: "python"
)

# シェルスクリプトの実行
send_command(
  command: "backup_data.sh",
  container: "python"
)
```

コマンドは `/monadic/data` を作業ディレクトリとして実行されるので、スクリプトは共有フォルダのほかのファイルに相対パスで届きます。スクリプトを呼ぶアプリの書き方は、[追加アプリの開発](../advanced-topics/develop_apps.md)を参照してください。
