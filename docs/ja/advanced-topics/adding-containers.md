# Docker コンテナの追加

## コンテナ追加の方法

Docker コンテナを追加するには、`~/monadic/data/services` または `~/monadic/data/apps/<アプリ名>/services` にフォルダを作り、次のファイルを置きます。

- `compose.yml`
- `Dockerfile`
- コンテナで必要なそのほかのファイル

ビルドするには、**Actions → Build User Containers** を選びます。次のことが行われます。

1. それらの `services` フォルダにある `compose.yml` をすべて探す
2. `--no-cache` でコンテナをビルドする
3. ビルドのログを `~/monadic/log/docker_build.log` に書く

Start では、ユーザーのコンテナは再ビルドされません。コンテナの定義を加えたり変えたりしたら、もう一度 **Build User Containers** を実行してください。

ユーザーのコンテナがあると、Monadic Chat は `~/monadic/config/compose.yml` を書き出し、システムのコンテナとユーザーのコンテナをまとめて扱います。コンテナは Start でいっしょに起動し、いっしょに止まります。

## 最小限の例

### compose.yml
```yaml
services:
  my_service:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: monadic-chat-my-service-container
    networks:
      - monadic-chat-network
    volumes:
      - ~/monadic/data:/monadic/data
      - ~/monadic/data/apps:/monadic/data/apps:ro
      - ~/monadic/data/helpers:/monadic/data/helpers:ro
      - ~/monadic/data/services:/monadic/data/services:ro
    environment:
      - MY_ENV_VAR=value

networks:
  monadic-chat-network:
    driver: bridge
```

### Dockerfile
```dockerfile
FROM ubuntu:22.04

# Install your dependencies
RUN apt-get update && apt-get install -y \
    your-packages-here && \
    rm -rf /var/lib/apt/lists/*

# Copy your files
COPY your-script.sh /usr/local/bin/

# Set working directory
WORKDIR /monadic/data

# Keep container running
CMD ["tail", "-f", "/dev/null"]
```

## 重要な要件

1. **ネットワーク**：コンテナを `monadic-chat-network` につなぎます。例のとおり `driver: bridge` で定義してください。システムのコンテナも同じ定義を使っています。
2. **共有フォルダ**：`~/monadic/data` を `/monadic/data` にバインドマウントします。`apps`、`helpers`、`services` は、システムのコンテナと同じく読み取り専用でマウントしてください。コンテナの中で実行されたコードが、Monadic Chat の読み込むアプリやヘルパーを書き換えられないようにするためです。
3. **コンテナ名**：`monadic-chat-<名前>-container` という名前にします。アプリからは `send_command(command: "...", container: "<名前>")` でコマンドを実行できます。[アプリの開発](develop_apps.md#calling-functions-in-the-app)を参照してください。
4. **動かし続ける**：`tail -f /dev/null` のようなコマンドで、コンテナが動き続けるようにします。

## 参考

リポジトリにあるシステムのコンテナが、そのまま完全な例になります。たとえば [GitHub](https://github.com/yohasebe/monadic-chat) の `docker/services/python/compose.yml` と `docker/services/python/Dockerfile` です。ただし、compose の `profiles`、`image`、`cache_from`、**Install Options** で決まるビルド引数は、システムのコンテナだけに要るもので、ユーザーのコンテナには要りません。

## トラブルシューティング

- **ビルドが失敗する**：`~/monadic/log/docker_build.log` を確かめてください。
- **コンテナが起動しない**：`compose.yml` の書き方と、ネットワークの定義を確かめてください。
- **共有フォルダのファイルが見えない**：`~/monadic/data:/monadic/data` のマウントを確かめてください。
- **ユーザーのコンテナが見つからない**：`services` フォルダに `compose.yml` がないと、ビルドでそのように表示されます。
