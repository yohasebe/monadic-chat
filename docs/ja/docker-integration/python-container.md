# 標準 Python コンテナ

Monadic Chat では、Python コンテナを使用して Python のコードを実行することができます。標準 Python コンテナは、`monadic-chat-python-container` という名前で提供されています。Python コンテナを使用することで、AI エージェントが Python のコードを実行し、その結果を返すことができます。

標準 Python コンテナは下記の Dockerfile で構築されています。

?> このページで示すプログラム例は、GitHubの [monadic-chat](https://github.com/yohasebe/monadic-chat) レポジトリ（`main`ブランチ）のコードを直接参照しています。

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/python/Dockerfile ':include :type=code dockerfile')

## 事前インストール済みLaTeXパッケージ

PythonコンテナにはConcept VisualizerやSyntax Treeなどの図形生成アプリのための包括的なLaTeXサポートが含まれています：

### コアLaTeXパッケージ
- `texlive-latex-base` - 基本的なLaTeX機能
- `texlive-latex-extra` - 追加のLaTeXパッケージとツール
- `texlive-fonts-recommended` - 標準LaTeXフォント
- `texlive-lang-chinese`、`texlive-lang-japanese`、`texlive-lang-korean` - CJK言語サポート
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
- 設定ファイル: `/monadic/matplotlibrc`
- これにより、matplotlibのプロットや図で日本語テキストが正しく表示されます

日本語テキストを含むチャートやプロットを生成する場合、追加の設定なしで自動的にフォントが使用されます。

## ライブラリの追加

追加のライブラリをインストールする場合は、下記のいずれかを行なってください。

- 共有フォルダの `pysetup.sh` にインストールスクリプトを追加して、Monadic Chat の環境構築時にライブラリをインストール（下記の例を参照）
- [Dockerコンテナへのアクセス](./docker-access)を参照して、Monadic Chat の環境構築後に Python コンテナにログインしてライブラリをインストール
- [Dockerコンテナの追加](./adding-containers)を参照して、カスタマイズした Python コンテナを追加
- [GitHub Issues](https://github.com/yohasebe/monadic-chat/issues) でリクエストを送信

## `pysetup.sh` の利用

Python コンテナに追加のライブラリをインストールする場合、`pysetup.sh` にインストールスクリプトを追加してください。`pysetup.sh` は Monadic Chat のビルド時に自動的に共有フォルダい内に作成されます。インストールスクリプトを追加して、Monadic Chatのメニュー項目から `Rebuild` を実行すると、上記の`Dockerfile`の最後に追加されたスクリプトが実行され、ライブラリがインストールされます。スクリプトの例を以下に示します。


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
python -m spacy download en_core_web_sm
python -m spacy download en_core_web_lg
```

### 日本語形態素解析ライブラリのインストール

```sh
# Install MeCab
apt-get update && apt-get install -y --no-install-recommends \
    mecab libmecab-dev mecab-utils mecab-ipadic-utf8 \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /etc/mecabrc /usr/local/etc/mecabrc
# Install mecab-python3
pip install --no-cache-dir --default-timeout=1000 \
    mecab-python3 unidic-lite
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
python -m spacy download ja_core_news_sm
```

### Matplotlib設定のカスタマイズ

matplotlibの設定をさらにカスタマイズする必要がある場合は、共有フォルダに`matplotlibrc`ファイルを作成または変更できます。このファイルはコンテナのセットアップ中に適切な場所にコピーされます：

```ini
# matplotlibrc設定の例
font.family: Noto Sans CJK JP
font.size: 12
axes.unicode_minus: False
```
