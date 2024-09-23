# レシピ・ファイルの例

## シンプルなアプリ（Math Tutor）

<details>
<summary>レシピ・ファイル（math_tutor.rb）</summary>

![chat_app.rb ](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/math_tutor/math_tutor_app.rb ':include :type=code')

</details>

## 関数定義を含むアプリ（Wikipedia）

<details>
<summary>レシピ・ファイル（wikipedia.rb）</summary>

![chat_app.rb ](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/wikipedia/wikipedia_app.rb ':include :type=code')

</details>

<details>
<summary>関数定義ファイル（wikipedia_agent.rb</summary>

![chat_app.rb ](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/lib/monadic/agents/wikipedia_agent.rb ':include :type=code')

</details>

アプリの中で関数を使用するには次の手順に従います。

- システム・プロンプトの中で関数の使い方を説明します。
- `@settings`ハッシュに`tools`キーを追加し、使用する関数の定義をリストで指定します。関数定義の方法は言語モデルのベンダーによって異なります。OpenAIHelperモジュールをインクルードしているアプリの場合は、[OpenAI: Function calling](https://platform.openai.com/docs/guides/function-calling)を参照してください。
- `tools`キーに指定された関数をRubyで定義します。関数はレシピ・ファイルのクラス内に記述するか、もしくは別のファイルの中で、`MonadicAgent`モジュールのインスタンスメソッドとして記述します。

## 出力形式の指定を含むアプリ（Novel Writer）

Monadic ChatではJSON形式で出力する場合の特別なモード（`monadic`モード）があります。詳細については[Monadicモード](/ja/monadic-mode)も参照してください。

<details>
<summary>レシピファイル（novel_writer_app.rb</summary>

![chat_app.rb ](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

`OpenAIHelper`をインクルードしたアプリで出力形式を指定するには次の手順に従います。

- システム・プロンプトの中でJSON形式で出力することを明記します。
- `@settings`ハッシュに`monadic`キーを追加し、値として`true`を指定します。
- `@settings`ハッシュに`response_format`キーを追加し、出力時に用いるべきJSONの形式を指定します。指定方法は[OpenAI: Structured outputs](https://platform.openai.com/docs/guides/structured-outputs)を参照してください。

## 独自のコンテナを用いたアプリ

[Dockerコンテナの追加](adding-containers.md)のセクションを参照してください。
