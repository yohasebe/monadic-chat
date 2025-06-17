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

- **Code Interpreter**: コード実行時に生成される中間ファイルや結果ファイル（CSVファイル、テキストファイル、画像ファイルなど）
- **Image Generator**: 生成された画像ファイル（PNG、JPEG、WebP形式）
- **Video Generator**: 生成された動画ファイル（MP4形式）
- **Jupyter Notebook**: Jupyterノートブック`.ipynb`ファイル
- **Video Describer**: 動画から抽出された画像フレーム（PNG形式）と音声（MP3形式）
- **Speech Draft Helper**: 生成された音声ファイル（OpenAI/ElevenLabsはMP3形式、GeminiはWAV形式）
- **Syntax Tree**: 生成された構文木図（SVG形式）
- **Concept Visualizer**: 生成された概念図（SVG形式）
- **Mermaid Grapher**: 生成されたダイアグラムのプレビュー画像（PNG形式）
- **DrawIO Grapher**: 生成されたダイアグラムファイル（.drawio形式）
- **Visual Web Explorer**: キャプチャされたウェブサイトのスクリーンショット（PNG形式）

ファイルはタイムスタンプまたは一意の識別子を含むファイル名で共有フォルダに直接保存されます。不要なファイルは定期的に削除することをお勧めします。

## Monadic Chatのディレクトリ構造

Monadic Chatを初回起動すると、以下のディレクトリ構造が自動的に作成されます：

```
~/monadic/
├── config/         # 設定ファイル（env、rbsetup.sh、pysetup.sh、olsetup.sh）
├── data/           # 共有フォルダ（コンテナから/monadic/dataとしてアクセス可能）
│   ├── apps/       # カスタムアプリケーション
│   ├── helpers/    # ヘルパーRubyファイル
│   ├── plugins/    # 独自のappsとhelpersを持つプラグイン
│   └── scripts/    # すべてのコンテナからアクセス可能な実行可能スクリプト
├── log/            # ログファイル（server.log、docker_build.logなど）
└── ollama/         # Ollamaモデルストレージ（Ollamaコンテナをビルドした場合）
```

`data`フォルダがすべてのコンテナにマウントされる共有フォルダです。これらのサブフォルダは追加アプリを開発する際にカスタムコンテンツを整理するために使用されます。追加アプリの開発方法については、[追加アプリの開発](../advanced-topics/develop_apps.md)を参照してください。

**`apps`**

基本アプリ以外の追加アプリケーションを格納するフォルダです。各アプリは`apps`ディレクトリ内の独自のサブフォルダに配置します。

**`helpers`**

アプリ内で使用する関数（メソッド）を含むヘルパーRubyファイルを格納するフォルダです。これらのヘルパーファイルはアプリのレシピファイルより前に読み込まれ、複数のアプリで共通のコードを整理・再利用できます。

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

Monadic Chatのプラグインを格納するフォルダです。各プラグインは個別のフォルダで構成され、その中に独自の`apps`と`helpers`サブフォルダを持つことができます。プラグインフォルダの中に`scripts`サブフォルダを持つことはできません。スクリプトは共有フォルダのルートにあるメインの`scripts`ディレクトリに配置する必要があります。
