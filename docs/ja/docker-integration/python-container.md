# 標準 Python コンテナ

Monadic Chat では、Python コンテナを使用して Python のコードを実行することができます。標準 Python コンテナは、`monadic-chat-python-container` という名前で提供されています。Python コンテナを使用することで、AI エージェントが Python のコードを実行し、その結果を返すことができます。

標準 Python コンテナは下記の Dockerfile で構築されています：

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

# Install Python packages
RUN pip install -U pip && \
    pip install --no-cache-dir --default-timeout=1000 \
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

## 事前インストール済みLaTeXパッケージ

PythonコンテナにはConcept VisualizerやSyntax Treeなどの図形生成アプリのための包括的なLaTeXサポートが含まれています：

### コアLaTeXパッケージ
- `texlive-latex-base` - 基本的なLaTeX機能
- `texlive-latex-extra` - 追加のLaTeXパッケージとツール
- `texlive-fonts-recommended` - 標準LaTeXフォント
- `texlive-lang-cjk` - CJK言語サポート
- `latex-cjk-all` - LaTeX用の完全なCJKサポート

### 特殊パッケージ
- `texlive-science` - 3D視覚化用の`tikz-3dplot`を含む科学パッケージ
- `texlive-pstricks` - PSTricksグラフィックパッケージ
- `texlive-latex-recommended` - 推奨LaTeXパッケージ
- `texlive-pictures` - TikZを含む図形描画パッケージ
- `dvisvgm` - ベクターグラフィックス生成用のDVIからSVGへのコンバータ

これらのパッケージにより、複雑な図表、フローチャート、3D視覚化、数学的図形の生成が可能になります。

## 日本語フォントサポート

Pythonコンテナには、matplotlibやその他の可視化ライブラリ用の日本語フォントサポートが含まれています。Noto Sans CJK JPフォントがインストールされ、`matplotlibrc`設定を通じて設定されています：

- フォントファミリー: Noto Sans CJK JP
- 設定ファイル: `/root/.config/matplotlib/matplotlibrc`
- これにより、matplotlibのプロットや図で日本語テキストが正しく表示されます

日本語テキストを含むチャートやプロットを生成する場合、追加の設定なしで自動的にフォントが使用されます。

## ライブラリの追加

追加のライブラリをインストールする場合は、下記のいずれかを行なってください。

- configフォルダの `pysetup.sh`（`~/monadic/config/pysetup.sh`）にインストールスクリプトを追加して、Monadic Chat の環境構築時にライブラリをインストール（下記の例を参照）
- [Dockerコンテナへのアクセス](./docker-access)を参照して、Monadic Chat の環境構築後に Python コンテナにログインしてライブラリをインストール
- [Dockerコンテナの追加](../advanced-topics/adding-containers)を参照して、カスタマイズした Python コンテナを追加
- [GitHub Issues](https://github.com/yohasebe/monadic-chat/issues) でリクエストを送信

## `pysetup.sh` の利用

Python コンテナに追加のライブラリをインストールする場合、configフォルダ（`~/monadic/config/`）に `pysetup.sh` ファイルを作成し、インストールコマンドを追加してください。このファイルが存在する場合、コンテナのビルドプロセス中に`Dockerfile`の最後でスクリプトが実行され、ライブラリがインストールされます。ファイルを作成または変更した後、変更を反映させるにはコンテナのリビルドが必要です。

### セットアップスクリプトの概要

Monadic Chatは、configフォルダ内に3つのオプションのセットアップスクリプトをサポートしています：

- `rbsetup.sh` - Rubyコンテナに追加のRuby gemをインストールする
- `pysetup.sh` - Pythonコンテナに追加のPythonパッケージをインストールする
- `olsetup.sh` - Ollamaコンテナのビルド時にOllamaモデルをダウンロードする

これらのスクリプトは自動的に作成されません。コンテナ環境をカスタマイズしたい場合は、手動で作成する必要があります。以下は`pysetup.sh`スクリプトの例です。


### 自然言語処理ライブラリのインストール

```sh
# Install NLP libraries, data, and models
pip install --no-cache-dir --default-timeout=1000 \
    scikit-learn \
    gensim\
    librosa \
    wordcloud \
    nltk \
    textblob \
    spacy==3.7.5

# Download NLTK data
python -m nltk.downloader all
# Download spaCy models
python -m spacy download en_core_web_lg
```

### 日本語形態素解析ライブラリのインストール

```sh
# Install MeCab
apt-get update && apt-get install -y --no-install-recommends \
    mecab libmecab-dev mecab-utils mecab-ipadic-utf8 \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
# Install mecab-python3
pip install --no-cache-dir --default-timeout=1000 mecab-python3
```

### spaCy の日本語モデルのインストール

```sh
# Install Rust so that spaCy can handle Japanese
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
export PATH="$HOME/.cargo/bin:$PATH"
pip install setuptools-rust
pip install sudachipy==0.6.8

# Download spaCy models
python -m spacy download ja_core_news_md
```


## Flask APIサーバー

Pythonコンテナはポート5070でFlask APIサーバーを実行し、トークン化サービスを提供します：

- **場所**: `/monadic/flask/flask_server.py`
- **ポート**: 5070
- **エンドポイント**:
  - `/health` - ヘルスチェックエンドポイント
  - `/warmup` - トークナイザーエンコーディングの事前読み込み
  - `/count_tokens` - テキストのトークン数をカウント
  - `/get_tokens_sequence` - テキストからトークンシーケンスを取得
  - `/decode_tokens` - トークンをテキストにデコード
  - `/get_encoding_name` - モデルのエンコーディング名を取得

Flaskサーバーはコンテナ起動時に自動的に開始され、Rubyバックエンドが使用する必須のトークン化サービスを提供します。

## スクリプトディレクトリ構造

Pythonコンテナには `/monadic/scripts/` 以下のサブディレクトリに整理された各種ユーティリティスクリプトが含まれています：

```
/monadic/scripts/
├── utilities/          # システムユーティリティ (sysinfo.sh, run_jupyter.sh)
├── cli_tools/          # CLIツール (content_fetcher.py, webpage_fetcher.py)
├── converters/         # ファイルコンバーター (pdf2txt.py, office2txt.py, extract_frames.py)
└── services/           # APIサービス (jupyter_controller.py)
```

これらのスクリプトはPATHに追加され、コンテナ内でコマンドとして実行できます。これらのサブディレクトリ内のすべてのPythonおよびシェルスクリプトには、コンテナビルド時に実行権限が設定されます。

