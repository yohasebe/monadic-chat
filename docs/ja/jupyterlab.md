# JupyterLabとの連携

Monadic Chatには、JupyterLabを起動する機能があります。JupyterLabは、データサイエンスや機械学習のための統合開発環境（IDE）です。JupyterLabを使用することで、Pythonを用いてデータの分析や可視化を行うことができます。

## JupyterLabの起動

Monadic Chatコンソールの`Actions/Start JupyterLab`メニューをクリックすると、JupyterLabが起動します。JupyterLabは、`http://localhost:8889`でアクセスできます。

![Action menu](/assets/images/action-menu.png ':size=120')

JupyterLabを起動すると、`/monadic/data`をホームディレクトリとしてJupyterLabが起動します。このため、JupyterLab内でも共有フォルダ内のファイルにアクセスできます。

![JupyterLab Terminal](/assets/images/jupyterlab-terminal.png ':size=600')

## JupyterLabの停止

JupyterLabを停止するには、JupyterLabのタブを閉じるか、Monadic Chatコンソールの`Actions/Stop JupyterLab`メニューをクリックします。

## JupyterLabアプリの利用

Monadic Chatの基本アプリ`Jupyter Notebook`では、AIエージェントとのチャットを通じて次のようなことができます。

- JupyterLabの起動と停止
- 共有フォルダへの新規ノートブックの作成
- 共有フォルダ内のノートブックの読み込み
- ノートブックへの新規セルの追加
