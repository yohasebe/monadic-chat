# Dockerコンテナの追加

## コンテナ追加の方法

新たなDockerコンテナを利用可能にするには、`~/monadic/data/services`に新しいフォルダを作成してその中に下記のファイルを配置します。

- `compose.yml`
- `Dockerfile`

参考として、標準で組み込まれているPythonコンテナの`compose.yml`と`Dockerfile`を以下に示します。`compose.yml`では、新しいコンテナの名前を`services`の下に追加します。

<details>
<summary>compose.yml</summary>

[compose.yml](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/python/compose.yml ':include :type=code')

</details>

`Dockerfile`では、新しいコンテナの構築方法を記述します。Dockerfileの中でCOPYするファイルは、`compose.yml`および`Dockefile`と同じディレクトリに配置します。

<details>
<summary>Dockerfile</summary>

[Dockerfile](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/python/Dockerfile ':include :type=code dockerfile')

</details>

コンテナを追加するにはMonadic Chatを再構築する必要があります。その際、`~/monadic/data`ディレクトリで`docker-compose.yml`ファイルが自動生成されます。このファイルはイメージとコンテナを削除するためにも使用されるので、変更や削除をしないようにしてください。

## コンテナ追加の例

新しいコンテナをアプリ内で実際に利用するには、そのコンテナ上でAPIエンドポイントを公開して、アプリからアクセスできるようにするか、または`~/monadic/data/scripts/`に新しいスクリプトを追加して、そのコンテナを利用するコマンドを追加する必要があります。コンテナ上でAPIエンドポイントを公開して、アプリからアクセスする例としては[Ollamaコンテナの利用](/ja/ollama.md)を参照してください。`scripts`フォルダに新しいスクリプトを追加する例としては、下記を参照してください。


Syntax Analysisアプリを追加するため手順を以下に示します。コードはGitHubの[monadic-chat-extra](https://github.com/yohasebe/monadic-chat-extra)レポジトリからダウンロードできます。

```
~/monadic/data
├── apps
│   └── syntactic_analysis
│       ├── syntactic_analysis_app.rb
│       └── agents
│           ├── syntree_render_agent.rb
│           └── syntree_build_agent.rb
└── services
    └── rsyntaxtree
        ├── Dockerfile
        ├── compose.yml
        ├── Gemfile
        └── fonts/
```

`apps`フォルダにはアプリのスクリプトを配置します。サブフォルダの構成は任意で、`apps`フォルダ内のすべてのRubyスクリプトが読み込まれます。上記では`apps`フォルダ内に`syntactic_analysis`フォルダが作成され、さらにその中に`agents`フォルダが作成されていますが、フォルダ構成は変更可能です。

Monadic Chatのアプリとして認識されるためには、それらのRubyスクリプトの中で下記のように`MonadicApp`を継承したクラスを定義する必要があります（`NewApp`は任意のクラス名です）。また、使用する言語モデルのベンターを指定する必要があります。下記では`OpenAIHelper`モジュールをインクルードします。

```ruby
class NewApp < MonadicApp
  include OpenAIHelper
  @settings = {
    . . .
  }
end
```

MonadicAppを継承したクラスのインスタンス内で、AIエージェントが使用できる関数を定義するには、MonadicAgentモジュール内に記述します。上記では、`syntax_render_anget.rb`と`syntax_build_agent.rb`でこれを行っています。各ファイルは次のような構成になります。

```ruby
module MonadicAgent
  def method1
    . . .
  end

  def method2
    . . .
  end
end
```

こうして定義された関数を、AIエージェントにとって認識できるようにするためには、その使い方をアプリのシステム・プロンプトで説明すると共に、`@settings`ハッシュ内の`tools`キーに関数の情報をJSON形式で追加します。関数情報の具体的なスキーマは言語モデルのベンダーによって異なりますが、一般的には下記のような形式になります。

```JSON
{
  "name": "method1",
  "description": "This is a method1.",
  "args": [
    {
      "name": "arg1",
      "description": "This is an argument1.",
      "type": "string"
    },
    {
      "name": "arg2",
      "description": "This is an argument2.",
      "type": "string"
    }
  ]
}
```

