# JupyterLabとの連携

Monadic Chatには、JupyterLabを起動する機能があります。JupyterLabは、データサイエンスや機械学習のための統合開発環境（IDE）です。JupyterLabを使用することで、Pythonを用いてデータの分析や可視化を行うことができます。

## JupyterLabの起動

Monadic Chatコンソールの`Actions/Start JupyterLab`メニューをクリックすると、JupyterLabが起動します。

- JupyterLabは[http://localhost:8889](http://localhost:8889)または[http://127.0.0.1:8889](http://127.0.0.1:8889)でアクセスできます
- パスワードやトークンは不要です（ローカル使用専用に設定）

<!-- SCREENSHOT: Actionsメニュー - Start JupyterLabとStop JupyterLabのメニュー項目が表示されている様子 -->

JupyterLabを起動すると、`/monadic/data`をホームディレクトリとしてJupyterLabが起動します。このため、JupyterLab内でも共有フォルダ内のファイルにアクセスできます。

<!-- SCREENSHOT: JupyterLabターミナル - JupyterLabインターフェース内でTerminalが開かれ、カレントディレクトリが/monadic/dataとなっている様子 -->

## JupyterLabの停止

JupyterLabを停止するには、JupyterLabのタブを閉じるか、Monadic Chatコンソールの`Actions/Stop JupyterLab`メニューをクリックします。

## JupyterLabアプリの利用

Monadic Chatの基本アプリ`Jupyter Notebook`では、AIエージェントとのチャットを通じて次のようなことができます。

- JupyterLabの起動と停止
- 共有フォルダへの新規ノートブックの作成
- 共有フォルダ内のノートブックの読み込み
- ノートブックへの新規セルの追加

複数ステップにわたる複雑なタスクでは、アプリはまず番号付きの計画を提示し、ユーザーの承認を得てから実行します（Plan-Approve-Execute ワークフロー）。

## 異なるモードでのJupyterアクセス

### Standalone モード

Standalone モードでは、すべてのJupyter機能が完全に利用可能です：
- JupyterLabインターフェースは[http://127.0.0.1:8889](http://127.0.0.1:8889)でアクセス可能
- アプリケーションメニューに`Jupyter Notebook`アプリが表示される
- AIエージェントがJupyterノートブックの作成、変更、実行を行える

### Server モードでの制限 :id=server-mode-restrictions

Monadic Chatを[Server モード](basic-architecture.md#server-standalone-modes)で実行する場合、Jupyter機能はデフォルトで無効化され、**Jupyterアプリはアプリケーションメニューから非表示**になります。Server モードでは複数のデバイスからのネットワークアクセスが可能であり、Jupyterは共有フォルダへの完全なアクセス権限を持つ任意のコード実行を許すため、信頼できないユーザーがサーバーに到達できる環境では危険な組み合わせになるからです。

それでもServer モードでJupyterアプリを有効にするには、`~/monadic/config/env`ファイルに以下を追加してください：
```
ALLOW_JUPYTER_IN_SERVER_MODE=true
```

!> **警告**: この設定は信頼された環境でのみ有効にしてください。サーバーに到達できる全員が、共有フォルダへの完全なアクセス権限で任意のコードを実行できるようになります。

## JupyterLab使用のヒント

- **作業ディレクトリ**: JupyterLabは`/monadic/data`を作業ディレクトリとして起動します
- **永続的ストレージ**: `/monadic/data`に保存されたすべてのファイルはコンテナの再起動後も保持されます
- **Pythonパッケージ**: ノートブックのセルで `!uv pip install --no-cache package_name` により追加パッケージをインストールできます。再ビルド後も保持される永続的なインストール方法は[Pythonコンテナ](python-container.md)を参照してください
- **ターミナルアクセス**: JupyterLabのTerminalを使用してPythonコンテナに直接アクセスできます


## 日本語テキストサポート

Monadic ChatのJupyter Notebookアプリケーションには、matplotlibプロット用の自動日本語フォント設定が組み込まれています。

### 自動フォント設定

以下を含むJupyter notebookを作成または実行すると：
- 日本語テキスト（ひらがな、カタカナ、または漢字）
- matplotlibのインポートまたは使用

システムは自動的にフォント設定セルを挿入します：
1. 日本語フォント（Noto Sans CJK JPまたはIPAGothic）を使用するようmatplotlibを設定
2. フォント関連の警告を抑制
3. プロット内の日本語文字の適切な表示を保証

### 動作の仕組み

フォント設定コードは自動的に挿入されます：
- 最初のmatplotlibインポート文の後（存在する場合）
- またはノートブックの先頭（インポートが見つからない場合）
- 日本語テキストまたはmatplotlibの使用が検出された場合のみ
- まだ存在しない場合のみ（「font-setup」メタデータでタグ付け）

### サポートされているフォント

システムは以下のフォントを順番にチェックします：
1. Noto Sans CJK JP（推奨）
2. IPA Gothic
3. システム設定の日本語フォント

### 例

日本語テキストを含むノートブックを作成すると：

```python
import matplotlib.pyplot as plt
import numpy as np

# 日本語ラベルを含むプロット
plt.plot([1, 2, 3], [1, 4, 2])
plt.title('日本語のタイトル')
plt.xlabel('横軸')
plt.ylabel('縦軸')
plt.show()
```

システムはコードが実行される前に自動的にフォント設定を追加し、日本語テキストが正しく表示されるようにします。

### 技術詳細

#### フォントパス
システムは以下のフォントの場所をチェックします：
- `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`
- `/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc`
- `/usr/share/fonts/opentype/ipafont/ipag.ttf`
- `/usr/share/fonts/truetype/ipafont/ipag.ttf`

#### 設定
- フォントファミリー: sans-serif
- Unicodeマイナス: 無効（マイナス記号の表示問題を防止）
- 警告: 欠落グリフに対して抑制

### トラブルシューティング

日本語テキストがまだ表示されない場合：
1. Jupyterカーネルを再起動
2. すべてのセルを再実行
3. フォント設定セルが正常に実行されたことを確認
4. Pythonコンテナにフォントがインストールされていることを確認

### 注意事項

- この機能はすべてのJupyter Notebookアプリ（OpenAI、Claude、Gemini、Grok）で利用可能
- フォント設定は各ノートブックセッション内で永続的
- 手動設定は不要 - 自動です！

## 関連アプリ

- **Code Interpreter**: JupyterLabを開かずにチャット内でPythonコードを直接実行
- **Jupyter Notebook**: チャットを通じてJupyterノートブックを作成・管理するAIエージェント
- 両アプリはJupyterLabと同じPython環境を使用します

