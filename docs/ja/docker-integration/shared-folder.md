# 共有フォルダ

Monadic Chatを最初に起動すると、`~/monadic/data`ディレクトリが作成されます。このディレクトリは、Monadic ChatのDockerコンテナ内でファイルを共有するためのデフォルトの共有フォルダです。

Monadic Chatコンソールの`Shared Folder`ボタンをクリックすると、OS標準のファイルマネージャが起動し、共有フォルダを開くことができます。

![Monadic Chat Console](../assets/images/monadic-chat-console.png ':size=700')

このディレクトリにファイルを配置すると、Monadic ChatのDockerコンテナ内でそのファイルにアクセスできます。ローカルでの共有フォルダのパスは`~/monadic/data`ですが、各Dockerコンテナ内での共有フォルダのパスは、`/monadic/data`です。

コードを実行することができるアプリでは（例：Code Interpreterアプリ）、共有フォルダ内のファイルを読み込むことができます。ファイルを指定する際にはディレクトリは指定せずファイル名のみを指定します。

AIエージェント側で（function callingなどを用いて）何らかの処理を行う中で、中間ファイルが共有フォルダ内に保存されることがあります。定期的に確認して不要なファイルを削除することをお勧めします。

Monadic Chatコンソールの`Actions/Start JupyterLab`メニューを使用してJupyterLabを起動すると、`/monadic/data`をホームディレクトリとしてJupyterLabが起動します。したがって、JupyterLab内でも共有フォルダ内のファイルにアクセスできます。

## 共有フォルダに保存されるファイル

### 基本アプリが生成するファイル

- `code interpreter` などのアプリで実行されたコードの中間ファイルや結果ファイル
- `image generator` アプリで生成された画像ファイル
- `jupyter notebook` アプリで作成されたノートブックファイル
- `video describer` アプリが動画を分割して生成した画像ファイル
- `video describer` アプリが抽出した音声ファイル
- `speech draft helper` アプリで生成された音声ファイル

不要なファイルは定期的に削除することをお勧めします。

## 共有フォルダ内の構成

基本アプリ以外のアプリを開発したり追加したりするときには、共有フォルダ内で適切に必要なファイルやフォルダを配置する必要があります。以下は、共有フォルダ内に自動的に作成されるサブフォルダです。追加アプリの開発方法については、[追加アプリの開発](../advanced-topics/develop_apps.md)を参照してください。

**`apps`**

基本アプリ以外の追加アプリケーションを格納するフォルダです。

**`services`**

追加アプリケーションから用いるためのイメージやコンテナを作成するためのDocker関連ファイルを格納するフォルダです。

**`helpers`**

アプリ内で使用する関数（メソッド）を含むヘルパーファイルを格納するフォルダです。

**`scripts`**

実行可能なスクリプト（シェルスクリプト、Pythonスクリプト、Rubyスクリプトなど）を格納するフォルダです。ここに配置されたスクリプトは自動的に実行権限が付与され、コンテナのPATHに追加されるため、フルパスを指定せずに名前だけで直接実行できます。

### ユーザースクリプトの仕組み

1. **配置場所**: ホストマシンの`~/monadic/data/scripts`にスクリプトを配置
2. **コンテナパス**: コンテナ内では`/monadic/data/scripts`で利用可能
3. **自動権限設定**: 各コマンド実行前にスクリプトに実行権限が自動的に付与されます
4. **直接実行**: スクリプト名のみで呼び出し可能（例：`/monadic/data/scripts/my_script.py`ではなく`my_script.py`）
5. **コンテナサポート**: Ruby、Python、その他のコンテナで動作

### アプリでの使用例

```ruby
# カスタムPythonスクリプトの実行
send_command(
  command: "analyze_data.py input.csv output.json",
  container: "python"
)

# カスタムRubyスクリプトの実行
send_command(
  command: "process_text.rb document.txt",
  container: "ruby"
)

# シェルスクリプトの実行
send_command(
  command: "backup_data.sh",
  container: "python"  # またはbashを持つ任意のコンテナ
)
```

### 技術的詳細

- Monadic Chatの`send_command`メソッドは自動的に`/monadic/data/scripts`をPATH環境変数に追加します
- コマンド実行時の作業ディレクトリは`/monadic/data`に設定されます
- スクリプトは相対パスを使用して共有フォルダ内の他のファイルにアクセスできます
- この仕組みにより、コアコードを変更せずにMonadic Chatの機能を拡張できます

**`plugins`**

Monadic Chatのプラグインを格納するフォルダです。各プラグインは個別のフォルダで構成され、その中に独自の`apps`、`helpers`、`services` サブフォルダを持つことができます。プラグイン・フォルダの中に`scripts`サブフォルダを持つことはできません。
