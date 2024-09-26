# Dockerコンテナの追加

## コンテナ追加の方法

新たなDockerコンテナを利用可能にするには、`~/monadic/data/services`に新しいフォルダを作成してその中に下記のファイルを配置します。

- `compose.yml`
- `Dockerfile`

コンテナを追加するにはMonadic Chatを再構築する必要があります。その際、`~/monadic/data`ディレクトリで`docker-compose.yml`ファイルが自動生成されます。このファイルはイメージとコンテナを削除するためにも使用されるので、原則として手動で変更や削除をしないようにしてください。

## 必要なファイルの記述例

参考として、標準で組み込まれているPythonコンテナの`compose.yml`と`Dockerfile`を以下に示します。`compose.yml`では、サービス名を`services`の直下に追加して（ここでは`python_service`）、その下に必要事項を記述します。Dockerfileの中でCOPYするファイルは、`compose.yml`および`Dockefile`と同じディレクトリに配置します。

### compose.yml

<details open="true">
<summary>compose.yml</summary>

[compose.yml](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/python/compose.yml ':include :type=code')

</details>

### Dockerfile

`Dockerfile`では、新しいコンテナの構築方法を記述します。

<details open="true">
<summary>Dockerfile</summary>

[Dockerfile](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/python/Dockerfile ':include :type=code dockerfile')

</details>

