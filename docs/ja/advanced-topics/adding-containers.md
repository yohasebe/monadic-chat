# Dockerコンテナの追加

?> このページで示すプログラム例は、GitHubの [monadic-chat](https://github.com/yohasebe/monadic-chat) レポジトリ（`main`ブランチ）のコードを直接参照しています。不具合をみつけた場合は pull request を送ってください。

## コンテナ追加の方法

新たなDockerコンテナを利用可能にするには、`~/monadic/data/services`または`~/monadic/data/apps/<アプリ名>/services`に新しいフォルダを作成して、以下のファイルを配置します：

- `compose.yml`
- `Dockerfile`
- コンテナで必要なその他のファイル

コンテナをビルドするには、Actionsメニューの `Build User Containers` オプションを使用します。このプロセスでは：
1. `services`ディレクトリおよびアプリ固有の`services`フォルダ内のユーザーコンテナを検索
2. 各コンテナを`--no-cache`フラグでビルド
3. ネットワークとボリュームマウントを自動設定
4. ビルドプロセスを`~/monadic/log/docker_build.log`に記録

?> **重要**: ユーザー定義コンテナはMonadic Chat起動時に自動的には構築されません。ユーザーコンテナ定義を追加または変更した後は、`Build User Containers` メニューオプションを使用して手動で構築する必要があります。

ユーザーコンテナが存在する場合、Monadic Chatは自動的に`~/monadic/config/compose.yml`ファイルを生成し、システムコンテナとユーザーコンテナの両方を含めます。このファイルはDocker Composeによってすべてのコンテナを一緒に管理するために使用されます。

## 最小限の例

必要最小限の構成例を示します：

### compose.yml
```yaml
services:
  my_service:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: my-custom-container
    networks:
      - monadic-chat-network
    volumes:
      - data:/data
    environment:
      - MY_ENV_VAR=value

networks:
  monadic-chat-network:
    external: true

volumes:
  data:
    external: true
    name: monadic-chat_data
```

### Dockerfile
```dockerfile
FROM ubuntu:22.04

# 依存関係のインストール
RUN apt-get update && apt-get install -y \
    your-packages-here && \
    rm -rf /var/lib/apt/lists/*

# ファイルのコピー
COPY your-script.sh /usr/local/bin/

# 作業ディレクトリの設定
WORKDIR /data

# コンテナを実行状態に保つ
CMD ["tail", "-f", "/dev/null"]
```

## 重要な要件

1. **ネットワーク**: 他のサービスと通信するため`monadic-chat-network`に接続する必要があります
2. **ボリューム**: `~/monadic/data`のファイルにアクセスするため、共有`data`ボリュームをマウントします
3. **コンテナ名**: 一意でわかりやすいコンテナ名を使用してください
4. **実行維持**: `tail -f /dev/null`のようなコマンドでコンテナを実行状態に保ちます

## 完全な例

実際に動作する完全な例として、Monadic Chatに含まれるPythonコンテナ（リポジトリの`docker/services/python/`）を参照してください。以下のリストでは繰り返し部分をコメントで省略しています。完全なファイルはリポジトリを確認してください。なお、ここに示す設定の一部（composeの`profiles`、`cache_from`、インストールオプション連動のビルド引数）はシステムコンテナ固有のもので、ユーザーコンテナには不要です。

### compose.yml

<details>
<summary>Pythonコンテナ compose.yml</summary>

```yaml
services:
  python_service:
    profiles: ["python"]
    image: yohasebe/python
    build:
      context: .
      dockerfile: Dockerfile
      # ビルド済みデフォルトイメージをレイヤーキャッシュとして再利用し、
      # ローカルビルドでは有効化したオプション層のみをビルドする
      cache_from:
        - ghcr.io/yohasebe/monadic-python:${MONADIC_IMAGE_TAG:-latest}
      args:
        PROJECT_TAG: "monadic-chat"
        INSTALL_LATEX: ${INSTALL_LATEX:-false}
        # ... インストールオプションごとに1つのビルド引数（PYOPT_NLTK、
        # PYOPT_SPACY、PYOPT_GENSIM、PYOPT_LIBROSA、PYOPT_MEDIAPIPE、
        # PYOPT_TRANSFORMERS、IMGOPT_IMAGEMAGICK）
    ports:
      - "${HOST_BINDING:-127.0.0.1}:8889:8889"
    container_name: monadic-chat-python-container
    volumes:
      - data:/monadic/data
      - ~/monadic/data:/monadic/data
    command: ["sleep", "infinity"]
    networks:
      - monadic-chat-network
```

</details>

### Dockerfile

<details>
<summary>Pythonコンテナ Dockerfile</summary>

```dockerfile
FROM python:3.12-slim-bookworm
ARG PROJECT_TAG=monadic-chat
LABEL project=$PROJECT_TAG

# uv をインストール（高速なPythonパッケージインストーラ。再現性のためバージョン固定）
COPY --from=ghcr.io/astral-sh/uv:0.9.18 /uv /usr/local/bin/uv
ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# オプション機能のトグル（デフォルトは無効。上記composeのビルド引数
# 経由で「アクション → インストールオプション」から設定される）
ARG INSTALL_LATEX=false
ARG PYOPT_NLTK=false
# ... 残りのインストールオプションごとに1つのARG

# ベースOSパッケージ（デフォルトは軽量構成）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential wget curl git gnupg \
      python3-dev graphviz libgraphviz-dev pkg-config \
      libxml2-dev libxslt-dev \
      pandoc ffmpeg fonts-noto-cjk fonts-ipafont \
    && fc-cache -fv && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# ベースPythonパッケージ（再現性のためバージョン固定。ここでは省略:
# jupyterlab, numpy, pandas, matplotlib, scikit-learn, pdfplumber,
# selenium, opencv-python など — 完全なリストはリポジトリのDockerfileを参照）
RUN uv pip install --no-cache \
      jupyterlab~=4.5 numpy~=1.26 pandas~=2.3 matplotlib~=3.10 \
      scikit-learn~=1.5 pdfplumber~=0.11 selenium~=4.39 \
      opencv-python~=4.11
      # ...（省略）

# オプション: Concept Visualizer / Syntax Tree 用のLaTeX一式
#（インストールオプション有効時のみインストール）
RUN if [ "$INSTALL_LATEX" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
        texlive-xetex texlive-latex-base texlive-pictures \
        texlive-lang-cjk latex-cjk-all dvisvgm pdf2svg \
        # ...（省略） \
      && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# オプションのPythonライブラリ — オプションごとに個別の条件付きRUNとし、
# 変更のないオプションはレイヤーキャッシュを再利用
RUN if [ "$PYOPT_NLTK" = "true" ]; then uv pip install --no-cache nltk || true; else echo "skip nltk"; fi
# ... 残りのオプションごとに1つのRUN（spacy、gensim、librosa+madmom、
# mediapipe、transformers、ImageMagick）

# JupyterLabのユーザー設定
RUN mkdir -p /root/.jupyter/lab/user-settings
COPY @jupyterlab /root/.jupyter/lab/user-settings/@jupyterlab

# Matplotlibの設定
ENV MPLCONFIGDIR=/root/.config/matplotlib
RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

# スクリプトをコピーして実行権限を付与
COPY scripts /monadic/scripts
RUN find /monadic/scripts -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;
RUN mkdir -p /monadic/data/scripts

# 環境変数を設定（LLMから参照可能）
ENV PATH="/monadic/data/scripts:/monadic/scripts:/monadic/scripts/utilities:/monadic/scripts/services:/monadic/scripts/cli_tools:/monadic/scripts/converters:/monadic/scripts/music:${PATH}"
ENV FONT_PATH=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
ENV PIP_ROOT_USER_ACTION=ignore

# データディレクトリへのシンボリックリンクを作成
RUN ln -s /monadic/data /data

COPY Dockerfile /monadic/Dockerfile
```

</details>

## トラブルシューティング

- **ビルドが失敗する**: `~/monadic/log/docker_build.log`でエラーメッセージを確認
- **コンテナが起動しない**: `compose.yml`の構文とネットワーク設定を確認
- **共有ファイルにアクセスできない**: ボリュームマウントが正しく設定されているか確認
- **ネットワークの問題**: コンテナが`monadic-chat-network`上にあることを確認

## 注意事項

- ユーザーコンテナは`--no-cache`でビルドされ、常に最新の状態になります
- ビルドログは`~/monadic/log/docker_build.log`に保存されます
- ユーザーコンテナが見つからない場合、ビルドプロセスが通知します
- ユーザーコンテナはシステムコンテナとは別に管理されます

