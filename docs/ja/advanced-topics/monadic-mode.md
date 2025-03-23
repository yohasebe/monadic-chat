# Monadicモード

MonadicモードはMonadic Chatの特徴的な機能の一つです。Monadicモードでは、それまでのチャットでなされたやり取り、すなわち文脈を、定義された形式で随時更新しながら保持し、それを参照しながらチャットを行うことができます。

![Monadic Chat Architecture](../assets/images/monadic-messaging.svg ':size=200')

## 基本的な構造

Monadicモードでは、毎回のクエリで言語モデルに次の構造のオブジェクトを生成させることにより、「文脈」を保持します。オブジェクト中の`message`は、通常のチャットの中でAIエージェントが返すメッセージに相当します。`context`は、それまでのやり取りの中で蓄積された情報や、発話の背後で共有されるべき情報を保持します。

```json
{
  "message": "Hello, world!",
  "context": {
    "key1": "value1",
    "key2": "value2"
  }
}
```

コンピュータも人間も、会話を行う際には、言語表現として音声化あるいは文字化されたメッセージをやり取りすることだけにかかわっているわけではありません。会話の背後には、文脈や目的があり、常にそれらを参照したり更新したりしながら談話を進行させていきます。

人間どうしの会話においては、このような文脈の保持と参照が自然に行われますが、AIエージェントとの会話においても、このような文脈の保持と参照は有用です。あらかじめそうした「メタ情報」の形式や構造を定義しておくことで、AIエージェントとの会話がより目的性を備えたものになることが期待されます。

## 具体的な例

### Jupyter Notebook アプリの例

Monadic Chatの特徴の1つはDocker上のLinux環境にアクセスでき、ホストコンピュータとのファイル共有が可能であることです。この利点を生かして、Jupyter Notebookアプリでは、AIエージェントがユーザーに対してPythonのコードを提案することができます。ユーザーは、共有フォルダを通じてデータを提供することができ、またコードを実行して得た結果ファイルを受け取ることもできます。

Jupyter Notebook アプリでは、セルごとにコードが実行され、あるセルで定義された変数や関数は、それ以降のセルでも参照することができます。したがって、AIエージェントに次々とコードを提案してもらう際には、それまでのセルで定義された変数や関数を参照しながら、新たなコードを提案してもらうことが必要になります。また、現在どのようなライブラリやモジュールをインポートしているかについて把握しておくことも重要です。加えて、ノートブック自体のファイル名（URL）を保持しておく必要もあります。

Jupyter Notebookアプリでは、次のような情報をオブジェクトとして保持し、構成要素を更新したものが次の発言の文脈として使われます。

- メッセージ (string)
- 文脈 (hash)
    - ノートブックのファイル名 (string)
    - インポートされているライブラリ (array)
    - 定義されている変数 (array)
    - 定義されている関数と引数 (array)

定義されている変数や関数の詳細について、さらに情報が必要な場合は、ノートブック自体のソースコードを読み込みます。また、現在の実行環境でどのようなプログラムやライブラリが利用可能かについても、AIエージェントは自ら確認する方法が与えられています。

<details>
<summary>Recipe File (jupyter_notebook_app.rb)</summary>

![language_practice_plus_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/jupyter_notebook/jupyter_notebook_app.rb ':include :type=code')

</details>

### Novel Writer アプリの例

例えば、Novel Writerアプリでは、Monadicモードを使って小説を書くことができます。小説を書く際には、描き初めから終わりまで、登場人物や場所、物語の流れなどの情報を一貫した形で保持していくことが重要です。そのため、Novel Writerアプリでは次のような情報をオブジェクトとして保持し、構成要素を更新したものが次の発言の文脈として使われます。

- メッセージ (string)
- 文脈 (hash)
    - 全体的なプロット (string)
    - 目標とするテキストの長さ (int)
    - 現在までのテキストの長さ (int)
    - 使用言語 (string)
    - 現在までの内容の要約 (string)
    - 登場人物 (array)
    - 次の展開に向けての問い (string)

会話はユーザーとAIエージェントとのやりとりで進行します。ユーザーはAIエージェントに対して、小説の展開に関する指示を行います。AIエージェントは、その指示に基づいて作成した新たな文章をメッセージとして返しますが、それと同時に文脈を更新します。ユーザーは、AIエージェントが返した文章と文脈に埋め込まれた「問い」を参照しながら、次の指示を行います。

このように、ユーザーとAIエージェントがメッセージをやり取りする背後で「文脈」を保持し、それを参照しながら新たな発言を行うことがMonadicモードの特徴です。Monadicモードを使うことで、単なる発話の連続にとどまらない「談話」が可能になります。

<details>
<summary>Recipe File (novel_writer_app.rb)</summary>

![novel_writer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

### Language Practice Plus アプリの例

言語学習においては、対象言語を使っての会話練習が重要です。その際の会話内容は、あらかじめ決められたものであるより、その場での会話の流れに応じて変化することが望ましいと考えられます。しかしながら、母語での会話でなく、外国語での会話を行う場合、常に最適な表現を使うことが難しいことがあります。そこで、自身が使用した表現に対してAIエージェントが誤りを指摘したり、新たな表現の提案したりしてくれると、より効果的な言語練習が可能になります。

- メッセージ (string)
- 文脈 (hash)
  - 対象言語 (string)
  - アドバイス (array)

ここでの「文脈」は、一般的な意味での文脈とはやや異なるかもしれませんが、会話練習のプロセスの目的が何であるかを考えるとき、単なる「受け答え」の発言だけではない情報が同時並行で得られることは非常に有益です。Monadicモードは、AIエージェントとユーザーとの会話を現実的な目的という基盤に紐づけることができる機能です。

<details>
<summary>Recipe File (novel_writer_app.rb)</summary>

![language_practice_plus_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/language_practice_plus/language_practice_plus_app.rb ':include :type=code')

</details>
