# 標準 Python コンテナ

Monadic Chat では、Python コンテナを使用して Python のコードを実行することができます。標準 Python コンテナは、`monadic-chat-python-container` という名前で提供されています。Python コンテナを使用することで、AI エージェントが Python のコードを実行し、その結果を返すことができます。

標準 Python コンテナは下記の Dockerfile で構築されています。

?> このページで示すプログラム例は、GitHubの [monadic-chat](https//github.com/yohasebe/monadic-chat) レポジトリ（`nightly`ブランチ）のコードを直接参照しています。

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/python/Dockerfile ':include :type=code dockerfile')

追加のライブラリをインストールする場合は、下記のいずれかを行なってください。

1. [Dockerコンテナへのアクセス](/ja/docker-access)を参照して、Monadic Chat の環境構築後に Python コンテナにログインしてライブラリをインストール
2. [Dockerコンテナの追加](/ja/adding-containers)を参照して、カスタマイズした Python コンテナを追加
3. [GitHub Issues](https://github.com/yohasebe/monadic-chat/issues) でリクエストを送信
