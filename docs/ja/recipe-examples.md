# レシピ・ファイルの例

## シンプルなアプリ

シンプルなアプリを開発する方法については、[シンプルなアプリの追加方法](http://localhost:3000/#/ja/develop_apps?id=シンプルなアプリの追加方法)を参照してください。

<details open=true>
<summary>レシピ・ファイル例（math_tutor.rb）</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/math_tutor/math_tutor_app.rb ':include :type=code')

</details>

## 関数・ツールの定義を含むアプリ

アプリ内でAIエージェントに関数やツールを使用させる方法については、[関数・ツールの呼び出し](http://localhost:3000/#/ja/develop_apps?id=関数・ツールの呼び出し)を参照してください。

<details open=true>
<summary>レシピ・ファイル例（wikipedia.rb）</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/wikipedia/wikipedia_app.rb ':include :type=code')

</details>

<details open=true>
<summary>ヘルパー・ファイル例（wikipedia_helper.rb）</summary>

<!-- ![](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/lib/monadic/helpers/wikipedia_helper.rb ':include :type=code') -->

</details>

## 出力形式の指定を含むアプリ

Monadic ChatではJSON形式で出力する場合の特別なモード（`monadic`モード）があります。詳細については[Monadicモード](/ja/monadic-mode)も参照してください。

OpenAIの一部のモデル（`gpt-4o`など）では、レスポンスをJSON形式で行うこと確実にするために、`response_format`を指定することができます。指定方法については[OpenAI: Structured outputs](https://platform.openai.com/docs/guides/structured-outputs)を参照してください。

<details open=true>
<summary>レシピファイル例（novel_writer_app.rb）</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

## 独自のコンテナを用いたアプリ

[Dockerコンテナの追加](adding-containers.md)のセクションを参照してください。
