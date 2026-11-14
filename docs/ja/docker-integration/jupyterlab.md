# JupyterLab との連携

Monadic Chat は、Python によるデータの分析と可視化の環境である JupyterLab を、Python コンテナで起動できます。

## JupyterLab の起動

Monadic Chat のコンソールで **Actions → Open JupyterLab** を選びます。JupyterLab が動いていなければ起動し、ブラウザーで開きます。このメニューは、Monadic Chat が動いている間に使えます。

ページからノートブックを開いたときにも、JupyterLab が起動します。会話の中のノートブックのリンクか、[作業画面](../basic-usage/web-interface.md#work-screen)に表示したノートブックの下の **JupyterLab で開く** を押してください。ページは JupyterLab を起動していることを表示し、準備ができるとノートブックを開きます。履歴から会話を開いたときや、AI がノートブックを作って実行したときには、JupyterLab は起動しません。

- JupyterLab は [http://localhost:8889](http://localhost:8889)（または [http://127.0.0.1:8889](http://127.0.0.1:8889)）で開きます
- パスワードやトークンは要りません。JupyterLab には、お使いのコンピューターからだけ接続できます

<!-- SCREENSHOT: Monadic Chat Actions menu showing Open JupyterLab and Stop JupyterLab options -->

JupyterLab は共有フォルダ（`/monadic/data`）で起動するので、`~/monadic/data` に置いたファイルをそこで使えます。

<!-- SCREENSHOT: JupyterLab terminal window showing command prompt at /monadic/data directory -->

## JupyterLab の停止

**Actions → Stop JupyterLab** を選びます。ブラウザーのタブを閉じても JupyterLab は動き続け、Monadic Chat を止めると止まります。

## Jupyter Notebook アプリの利用

Jupyter Notebook アプリでは、チャットで AI エージェントにノートブックの作業を頼みます。エージェントは次のことができます。

- JupyterLab の起動と停止
- 会話のフォルダ（共有フォルダの `conversations/…/work/`）でのノートブックの作成と、その会話のノートブックの一覧
- セルの追加、編集、移動、削除と、セルの実行
- セルの出力の読み取りと、エラーになったセルの修正
- ノートブックに残っている出力の消去

エージェントが扱うのは、今の会話のノートブックです。共有フォルダの一番上にあるノートブックを扱うときは、`./analysis.ipynb` のように名前の前に `./` を付けて伝えます。履歴から続ける会話でも、その会話のノートブックはそのまま使えます。

エージェントが作ったり変えたりしたノートブックは、セルの出力（グラフを含む）と一緒に[作業画面](../basic-usage/web-interface.md#work-screen)に表示されます。

実行するたびに新しいカーネルが立ち上がり、ノートブックのすべてのセルを実行します。実行を止めるには **Cancel Query** を押します。

いくつもの手順がある作業では、アプリはまず番号付きの計画を示し、承認を待ってから実行します。

Jupyter Notebook アプリは、OpenAI、Anthropic、Gemini、xAI で使えます。

## JupyterLab を使うときのヒント

- **保存したファイル**：`/monadic/data` に保存したファイルは、お使いのコンピューターの `~/monadic/data` に残ります
- **Python のパッケージ**：ノートブックのセルで `!uv pip install --no-cache package_name` と実行すると、パッケージが入ります。入れたパッケージは、再ビルドや更新などでコンテナが作り直されるまで残ります。再ビルドの後も残すには[Python コンテナ](python-container.md)を参照してください
- **ターミナル**：JupyterLab の Terminal で、Python コンテナのシェルが開きます

## グラフの日本語

Jupyter Notebook アプリが、日本語を含むセルや matplotlib を使うセルを追加するときは、フォントを設定するセルも一緒に追加します。これで、matplotlib のグラフの日本語が、Python コンテナに入っている Noto Sans CJK JP で表示されます。

たとえば、次のコードのラベルは日本語で表示されます。

```python
import matplotlib.pyplot as plt

plt.plot([1, 2, 3], [1, 4, 2])
plt.title('日本語のタイトル')
plt.xlabel('横軸')
plt.ylabel('縦軸')
plt.show()
```

それでも日本語が表示されないときは、カーネルを再起動し、フォントの設定のセルからすべてのセルを実行し直してください。

## 関連するアプリ

- **Code Interpreter**：JupyterLab を開かずに、チャットで Python のコードを直接実行します
- **Jupyter Notebook**：チャットで Jupyter のノートブックを作成・編集します
- どちらのアプリも、JupyterLab と同じ Python の環境を使います
