# Dockerコンテナの追加

?> このページで示すプログラム例は、GitHubの [monadic-chat](https://github.com/yohasebe/monadic-chat) レポジトリ（`main`ブランチ）のコードを直接参照しています。不具合をみつけた場合は pull request を送ってください。

## コンテナ追加の方法

新たなDockerコンテナを利用可能にするには、`~/monadic/data/services`または`~/monadic/data/plugins`に新しいフォルダを作成して、以下のファイルを配置します：

- `compose.yml`
- `Dockerfile`
- コンテナで必要なその他のファイル

コンテナをビルドするには、Actionsメニューの `Build User Containers` オプションを使用します。このプロセスでは：
1. `services`と`plugins`ディレクトリ内のユーザーコンテナを検索
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

Monadic Chatに含まれるPythonコンテナの完全な実装例：

### compose.yml

<details>
<summary>Pythonコンテナ compose.yml</summary>

```yaml
services:
  python_service:
    image: yohasebe/python
    build:
      context: .
      dockerfile: Dockerfile
      args:
        PROJECT_TAG: "monadic-chat"
    ports:
      - "8889:8889"
      - "5070:5070"
    container_name: monadic-chat-python-container
    volumes:
      - data:/monadic/data
      - ~/monadic/data:/monadic/data
    command: /bin/sh -c "cd /monadic/flask && gunicorn --timeout 300 -b 0.0.0.0:5070 flask_server:app"
    networks:
      - monadic-chat-network
    depends_on:
      selenium_service:
        condition: service_started
```

</details>

### Dockerfile

<details>
<summary>Pythonコンテナ Dockerfile</summary>

```dockerfile
FROM python:3.10-slim-bookworm
ARG PROJECT_TAG
LABEL project=$PROJECT_TAG

# Install necessary packages
# LaTeX packages for Concept Visualizer:
# - texlive-latex-base: Basic LaTeX
# - texlive-latex-extra: Additional LaTeX packages
# - texlive-pictures: TikZ and PGF
# - texlive-science: Scientific diagrams (including tikz-3dplot)
# - texlive-pstricks: PSTricks for advanced graphics
# - texlive-latex-recommended: Recommended packages
# - texlive-fonts-extra: Additional fonts
# - texlive-plain-generic: Generic packages
# - texlive-lang-cjk: CJK language support
# - latex-cjk-all: Complete CJK support
# - dvisvgm: DVI to SVG converter
# - pdf2svg: PDF to SVG converter (backup option)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential wget curl git gnupg \
    python3-dev graphviz libgraphviz-dev pkg-config \
    libxml2-dev libxslt-dev \
    pandoc ffmpeg fonts-noto-cjk fonts-ipafont \
    imagemagick libmagickwand-dev \
    texlive-xetex texlive-latex-base texlive-fonts-recommended \
    texlive-latex-extra texlive-pictures texlive-lang-cjk latex-cjk-all \
    texlive-science texlive-pstricks texlive-latex-recommended \
    texlive-fonts-extra texlive-plain-generic \
    pdf2svg dvisvgm \
    && fc-cache -fv \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# uv をインストール（パッケージインストールの高速化）
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# uv を設定
ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Pythonパッケージをインストール
RUN uv pip install --no-cache \
    setuptools \
    wheel \
    jupyterlab ipywidgets plotly \
    numpy  pandas statsmodels \
    matplotlib seaborn \
    gunicorn tiktoken flask \
    pymupdf pymupdf4llm \
    selenium html2text \
    openpyxl python-docx python-pptx \
    requests beautifulsoup4 \
    lxml pygraphviz graphviz pydotplus networkx pyvis \
    svgwrite cairosvg tinycss cssselect pygal \
    pyecharts pyecharts-snapshot \
    opencv-python moviepy==2.0.0.dev2

# Set up JupyterLab user settings
RUN mkdir -p /root/.jupyter/lab/user-settings
COPY @jupyterlab /root/.jupyter/lab/user-settings/@jupyterlab

# Set up Matplotlib configuration
ENV MPLCONFIGDIR=/root/.config/matplotlib
RUN mkdir -p /root/.config/matplotlib
COPY matplotlibrc /root/.config/matplotlib/matplotlibrc

# Copy scripts and set permissions
COPY scripts /monadic/scripts
RUN find /monadic/scripts -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;
RUN mkdir -p /monadic/data/scripts

# Set environment variables (visible to LLM)
ENV PATH="/monadic/data/scripts:/monadic/scripts:/monadic/scripts/utilities:/monadic/scripts/services:/monadic/scripts/cli_tools:/monadic/scripts/converters:${PATH}"
ENV FONT_PATH=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
ENV PIP_ROOT_USER_ACTION=ignore

# Copy Flask application
COPY flask /monadic/flask

# Create symbolic link for data directory
RUN ln -s /monadic/data /data

COPY Dockerfile /monadic/Dockerfile

# copy `pysetup.sh` to `/monadic` and run it
COPY pysetup.sh /monadic/pysetup.sh
RUN chmod +x /monadic/pysetup.sh
RUN /monadic/pysetup.sh
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

