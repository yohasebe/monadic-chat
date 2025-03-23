# 基本構造

Monadic Chatでは、Dockerコンテナとして構築された仮想環境をシステムに組み込むことにより、言語モデルのAPIだけでは実現できない高度な機能を提供しています。

Dockerコンテ内にはユーザーとAIエージェントの両方がアクセス可能で、自然言語によるコミュニケーションを通じて協力し合いながら環境に変化を生じさせることが可能です。具体的には、ユーザーの指示のもとにAIエージェントがコマンドをインストールしたり、そのコマンドの使い方を教えたり、自らコマンドを実行して結果を返したりすることができます。

また、ホストコンピュータと個々のDockerコンテナとの間でデータを共有するための仕組みも提供しています。これにより、ユーザーは仮想環境とシームレスに連携でき、必要なファイルをAIエージェントに提供したり、AIエージェントにより生成されたファイルを取得したりすることができます。

![Basic Architecture](../assets/images/basic-architecture-ja.png ':size=800')


## 標準コンテナ

標準では下記のコンテナが構築されます。

**Rubyコンテナ**（`monadic-chat-ruby-container`）

Monadic Chatのアプリケーションを実行するために必要なコンテナです。Webインターフェイスを提供するためにも使用されます。

**Pythonコンテナ**（`monadic-chat-python-container`）

Monadic Chatの機能を拡張するためのPythonスクリプトを実行するために使用されます。JupyterLabもこのコンテナ上で実行されます。

使用しているアプリの例：`Code Interpreter`, `Jupyter Notebook`, `Video Describer`

**Seleniumコンテナ**（`monadic-chat-selenium-container`）

Seleniumを使用して仮想的なWebブラウザを操作して、Webページのスクレイピングを行うために使用されます。

使用しているアプリの例：`Code Interpreter`, `Content Reader`

**pgvectorコンテナ**（`monadic-chat-pgvector-container`）

Postgresql上にテキスト埋め込みのベクトルデータを保存するため、pgvectorを使用するためのコンテナです。

使用しているアプリの例：`PDF Navigator`

?> 追加のDockerコンテナを導入する方法については、[Dockerコンテナの追加](../advanced-topics/adding-containers.md)を参照してください。


