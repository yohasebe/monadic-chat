# 共有フォルダ

Monadic ChatのDockerコンテナ内でファイルを共有するためのフォルダを設定する方法について説明します。

Monadic Chatを最初に起動すると、`~/monadic/data`ディレクトリが作成されます。このディレクトリは、Monadic ChatのDockerコンテナ内でファイルを共有するためのデフォルトの共有フォルダです。

Monadic Chatコンソールの`Shared Folder`ボタンをクリックすると、OS標準のファイルマネージャが起動し、共有フォルダを開くことができます。

このディレクトリにファイルを配置すると、Monadic ChatのDockerコンテナ内でそのファイルにアクセスできます。各Dockerコンテナ内での共有フォルダのパスは、`/monadic/data`です。

コードを実行することができるアプリでは（例：Code Interpreterアプリ）、共有フォルダ内のファイルを読み込むことができます。ファイルを指定する際にはディレクトリは指定せずファイル名のみを指定します。

アプリ内部で何らかの処理を行う場合、中間ファイルを共有フォルダ内に保存することがあります。何らかの理由でアプリ上での処理が失敗した場合、共有フォルダ内のファイルを確認することで、処理の途中結果を確認することができます。

Monadic Chatコンソールの`Actions/Start JupyterLab`メニューを使用してJupyterLabを起動すると、`/monadic/data`をホームディレクトリとしてJupyterLabが起動します。このため、JupyterLab内でも共有フォルダ内のファイルにアクセスできます。

## 自動で作成されるサブフォルダ

Monadic ChatのDockerコンテナ内で自動的に作成されるサブフォルダについて説明します。

**`apps`**

基本アプリ以外の追加アプリケーションを格納するフォルダです。

**`services`**

追加アプリケーションから用いるためのイメージやコンテナを作成するためのDocker関連ファイルを格納するフォルダです。

**`helpers`**

アプリ内で使用する関数（メソッド）を含むヘルパーファイルを格納するフォルダです。

**`scripts`**

標準コンテナ内で実行可能なするシェルスクリプトを格納するフォルダです。ここでいう標準コンテナは下記のものを指します。

- `monadic-chat-ruby-container`
- `monadic-chat-python-container`
- `monadic-chat-selenium-container`
- `monadic-chat-pgvector-container`

**`plugins`**

Monadic Chatのプラグインを格納するフォルダです。各プラグインは個別のフォルダで構成され、その中に独自の`apps`、`helpers`、`services` サブフォルダを持つことができます。プラグイン・フォルダの中に`scripts`サブフォルダを持つことはできません。
