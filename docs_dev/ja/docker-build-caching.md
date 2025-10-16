# Dockerビルドキャッシング戦略

## 概要

Monadic Chatは、ビルド速度と信頼性のバランスを取るために、コンテナのインテリジェントなビルドキャッシングを使用します。戦略は、自動再ビルド（バージョン更新時や起動時）と手動再ビルド（メニューコマンド経由）で異なります。

## コンテナタイプ別ビルド戦略

### Rubyコンテナビルド戦略

Rubyコンテナビルドは、ビルドがトリガーされる方法によって異なるキャッシング戦略を使用します：

**1. バージョン更新時の自動再ビルド（STARTボタン）：**
- **トリガー**：アプリがバージョン不一致を検出（例：`v1.0.0-beta.4` → `v1.0.0-beta.5`）
- **キャッシュ戦略**：Dockerビルドキャッシュを使用（高速、約1-2分）
- **理由**：バージョン更新は通常アプリケーションコードのみを変更し、依存関係は変更しない
- **実装**：`FORCE_REBUILD`環境変数は設定されない
- **場所**：`docker/monadic.sh:366-371`が`FORCE_REBUILD:-false`をチェック

**2. メニューからの手動再ビルド（Actions → Build Ruby Container）：**
- **トリガー**：ユーザーがメニューから明示的にビルドを選択
- **キャッシュ戦略**：`--no-cache`を使用（完全再ビルド、約5-10分）
- **理由**：ユーザーがクリーンビルドを保証したい、またはシステム変更後に再ビルドしたい可能性がある
- **実装**：Electronが`FORCE_REBUILD=true`環境変数を設定
- **場所**：`app/main.js:618-620`が`buildEnv = { FORCE_REBUILD: 'true' }`を設定

**3. Dockerfile変更時の自動再ビルド：**
- **トリガー**：バージョン更新中にRuby Dockerfileの変更を検出
- **キャッシュ戦略**：`--no-cache`を使用（完全再ビルド）
- **理由**：Dockerfileの変更には、クリーンビルドが必要な依存関係の更新が含まれる可能性がある
- **実装**：`check_dockerfiles_changed()`関数がファイルハッシュをチェック

**バージョン更新検出フロー：**
```
STARTボタン押下
        ↓
確認：MONADIC_CHAT_IMAGE_TAG == MONADIC_VERSION?
        ↓
    ┌───No────┐
    │         │
    ↓         ↓
バージョン  バージョン
不一致     一致
    │         │
    ↓         └─→ 起動を継続
確認：Dockerfile変更？
    │
┌───┴───┐
│       │
Yes     No
│       │
↓       ↓
完全    Rubyのみ
再ビルド 再ビルド
│       │
↓       ↓
--no-cache  キャッシュ使用（高速）
（低速）    （1-2分）
```

**主要コード箇所：**
- バージョン比較：`docker/monadic.sh:1235`
- Dockerfile変更検出：`docker/monadic.sh:1237`
- FORCE_REBUILDチェック：`docker/monadic.sh:368`
- Electron FORCE_REBUILD設定：`app/main.js:619-620`

### Pythonコンテナビルド戦略

## 仕組み

### 完全ビルドフロー（Pythonコンテナ）

```
ユーザーがElectron UIでインストールオプションを変更
          ↓
Electronが~/monadic/config/envに保存
          ↓
ユーザーが「Build Python Container」をトリガー
          ↓
Electronが設定ファイルからenv varsを渡してmonadic.shを起動
          ↓
read_cfg_bool()がenv vars（優先度1）または設定ファイル（優先度2）を読み取り
          ↓
~/monadic/log/python_build_options.txtと比較
          ↓
    ┌─────────────────────┬──────────────────────┐
    │                     │                      │
オプション変更済み    オプション未変更     初回ビルド
    │                     │                      │
    ↓                     ↓                      ↓
--no-cache          キャッシュ使用        --no-cache
（15-30分）         （1-2分）            （15-30分）
    │                     │                      │
    └─────────────────────┴──────────────────────┘
                          ↓
              Dockerビルドが新しいイメージを作成
                          ↓
              yohasebe/python:latestとしてタグ付け
                          ↓
              ヘルスチェック合格？
                          ↓
                    ┌─────┴─────┐
                    │           │
                  Yes          No
                    │           │
                    ↓           ↓
          オプションを      古いイメージを保持
          .txtファイルに保存 一時イメージをクリーン
                    │           │
                    ↓           └─→ FAIL
          コンテナは実行中？
                    │
              ┌─────┴─────┐
              │           │
            Yes          No
              │           │
              ↓           ↓
    コンテナを再起動  再起動をスキップ
    （新イメージを使用）（新イメージは
                      次回起動時に使用）
              │           │
              └─────┬─────┘
                    ↓
              SUCCESS - 新イメージが使用中
```

### インストールオプション追跡

ビルドシステムは以下のインストールオプションを追跡します：
- `INSTALL_LATEX`：Syntax TreeとConcept Visualizer用LaTeXツールチェーン
- `PYOPT_NLTK`：Natural Language Toolkit
- `PYOPT_SPACY`：spaCy NLPライブラリ
- `PYOPT_SCIKIT`：scikit-learn機械学習ライブラリ
- `PYOPT_GENSIM`：トピックモデリングライブラリ
- `PYOPT_LIBROSA`：オーディオ分析ライブラリ
- `PYOPT_MEDIAPIPE`：コンピュータビジョンフレームワーク
- `PYOPT_TRANSFORMERS`：Hugging Face Transformers
- `IMGOPT_IMAGEMAGICK`：ImageMagick画像処理

### ビルド戦略

**オプションが変更されていない場合：**
- 高速再ビルドのためにDockerビルドキャッシュを使用（約1-2分）
- 実際に変更されたレイヤーのみを再ビルド
- ログ：`[INFO] Install options unchanged, using build cache for faster build`

**オプションが変更された場合：**
- `--no-cache`を使用して完全再ビルドを強制（約15-30分）
- 新しいパッケージが適切にインストールされることを保証
- 変更されたオプションをログに記録：`[INFO] Install options changed: INSTALL_LATEX(false→true)`
- ログ：`[INFO] Using --no-cache to ensure changes are applied`

**初回ビルドまたはオプションファイルが存在しない場合：**
- 安全のため`--no-cache`を使用
- ログ：`[INFO] First build or options file missing, using --no-cache`

### オプションファイルの場所

以前のビルドオプションは以下に保存されます：
```
~/monadic/log/python_build_options.txt
```

このファイルは、各ビルド成功後に自動的に作成/更新されます。

## ユーザーエクスペリエンス

### インストールオプションの変更

1. Electronアプリメニューを開く：**Actions → Install Options**
2. オプションを切り替え（例：Syntax Treeアプリ用にLaTeXを有効化）
3. **Save**をクリック
4. メニュー：**Actions → Build Python Container**
5. システムが変更を検出し、自動的に`--no-cache`を使用

期待されるログ出力：
```
[INFO] Install options changed: INSTALL_LATEX(false→true)
[INFO] Using --no-cache to ensure changes are applied
[HTML]: <p>Starting Python image build (atomic) . . .</p>
...
[INFO] Saved build options to ~/monadic/log/python_build_options.txt
[HTML]: <p>Restarting Python container to use new image...</p>
[INFO] Python container restarted successfully
```

システムは、ビルド成功後に自動的にPythonコンテナを再起動し、新しいイメージがすぐに使用されるようにします。

### 変更なしでの再ビルド

オプションを変更せずに再ビルドする場合、システムはキャッシュを使用します：
```
[INFO] Install options unchanged, using build cache for faster build
```

これは、ほとんどのレイヤーがキャッシュされているため、はるかに高速に完了します。

## 技術詳細

### 環境変数の優先順位

`monadic.sh`の`read_cfg_bool`関数は、以下の順序でオプションをチェックします：
1. **環境変数**（ビルド中にElectronによって渡される）
2. **設定ファイル**（`~/monadic/config/env`）
3. **デフォルト値**（通常`false`）

### 変更検出アルゴリズム

```bash
# 各オプションについて：
1. python_build_options.txtから以前の値を読み取る
2. 現在の値と比較
3. オプションが異なる場合 → use_no_cache=true
4. 適切なキャッシュ戦略でビルド
5. 成功時 → 現在のオプションをファイルに保存
6. Pythonコンテナが実行中の場合 → 新しいイメージを使用するために再起動
```

### これが重要な理由

**解決する問題：**
- Dockerのビルドキャッシュは、`ARG`値が変更されてもレイヤーを再利用できる
- `--no-cache`なしでは、`INSTALL_LATEX`を`false`から`true`に変更しても、`false`でビルドされたキャッシュレイヤーが使用される可能性がある
- これにより、正しいビルド引数にもかかわらずパッケージが欠落する結果になる

**解決策：**
- アプリケーションレベルで実際のオプション変更を検出
- 本当に必要な場合のみ`--no-cache`を強制
- 信頼性とビルド速度のバランス

### コンテナ自動再起動

ビルド成功後、システムはPythonコンテナが実行中の場合自動的に再起動します：

```bash
# コンテナが実行中かチェック
if docker ps --format '{{.Names}}' | grep -q "^monadic-chat-python-container$"; then
  # docker composeを使用して再起動
  docker compose restart python_service
fi
```

**これが必要な理由：**
- 新しいDockerイメージをビルドしても、実行中のコンテナは自動的に更新されない
- コンテナは再起動されるまで古いイメージを使い続ける
- 自動再起動なしでは、ユーザーが手動でコンテナを停止/起動する必要がある
- これは混乱を招く可能性がある：「再ビルドしたのにパッケージがまだ不足している！」

**実装場所：** `docker/monadic.sh:588-599`

### ビルドと再起動の成功を確認

ビルド完了後、コンテナが新しいイメージを使用していることを確認します：

```bash
# 1. コンテナ作成時刻を確認（最近のはず）
docker ps --filter "name=monadic-chat-python-container" --format "{{.CreatedAt}}"

# 2. コンテナが最新イメージを使用していることを確認
docker inspect monadic-chat-python-container --format='{{.Image}}' > /tmp/container_img
docker images yohasebe/python:latest --format "{{.ID}}" > /tmp/latest_img
diff /tmp/container_img /tmp/latest_img  # 同一であるべき

# 3. LaTeXビルドの場合、パッケージ数を確認
docker exec monadic-chat-python-container bash -c "dpkg -l | grep -i latex | wc -l"
# INSTALL_LATEX=trueの場合100+、falseの場合0を返すべき

# 4. 重要なツールが存在することを確認
docker exec monadic-chat-python-container bash -c "which dvisvgm && kpsewhich CJKutf8.sty"
```

## トラブルシューティング

### オプションが効果を発揮しない

オプションを変更してもパッケージがインストールされない場合：

1. **ビルドログを確認**（`~/monadic/log/docker_build_python.log`）：
   ```bash
   grep "Install options" ~/monadic/log/docker_build_python.log
   ```

2. **保存されたオプションを確認**：
   ```bash
   cat ~/monadic/log/python_build_options.txt
   ```

3. **完全再ビルドを強制**（必要な場合）：
   ```bash
   # オプションファイルを削除して--no-cacheをトリガー
   rm ~/monadic/log/python_build_options.txt
   # その後Electronメニューから再ビルド
   ```

### 手動Dockerビルド

`docker build`で手動ビルドする場合：
```bash
# ARG値を変更する場合は常に--no-cacheを使用
docker build --no-cache \
  --build-arg INSTALL_LATEX=true \
  -t yohasebe/python \
  docker/services/python
```

### 再ビルド後にコンテナが古いイメージを使用

**症状：** `INSTALL_LATEX=true`で再ビルドした後も、LaTeXパッケージ数が0を示す。

**診断：**
```bash
# コンテナの作成時刻を確認
docker ps -a --format "{{.Names}}\t{{.CreatedAt}}" | grep python

# 最新イメージのビルド時刻を確認
docker images yohasebe/python:latest --format "{{.CreatedAt}}"

# コンテナ作成時刻がイメージビルド時刻より前の場合、コンテナは古いイメージを使用
```

**原因：** Dockerビルドは新しいイメージを作成しますが、実行中のコンテナは更新しません。

**解決策（自動）：** ビルドシステムは、ビルド成功後に自動的にコンテナを再起動します（コミット`86d2bca6`で実装）。

**手動回避策（必要な場合）：**
```bash
docker compose restart python_service
# または
docker stop monadic-chat-python-container
docker rm monadic-chat-python-container
docker compose up -d python_service
```

## 開発ノート

### 実装から得られた主要な学び

**1. 環境変数の伝播**
- Electronアプリは`~/monadic/config/env`を読み取り、`spawn(..., { env: {...process.env, ...envConfig} })`で変数を渡す
- 元の`read_cfg_bool`は設定ファイルのみをチェックし、環境変数をチェックしなかった
- **修正：** `eval echo "\${key}"`を使用して環境変数を最初にチェックするように変更
- **場所：** `docker/monadic.sh:392-420`

**2. Dockerビルドキャッシュの動作**
- Dockerは`ARG`値が変更されてもレイヤーをキャッシュする
- 例：`ARG INSTALL_LATEX=true` vs `false`でも同じキャッシュされた`RUN if [ "$INSTALL_LATEX" = "true" ]`レイヤーが使用される可能性がある
- **証拠：** `docker history`は、`--build-arg INSTALL_LATEX=true`を渡しているにもかかわらず、最終イメージに`INSTALL_LATEX=false`を示した
- **根本原因：** 条件付きRUNコマンドは実行時に評価されるが、キャッシュキーはDockerfileテキストのみに基づく
- **解決策：** ARG値が実際に変更された場合に`--no-cache`を使用

**3. コンテナ vs イメージのライフサイクル**
- **イメージ：** 一度ビルドされ、不変、タグ付けされる（例：`yohasebe/python:latest`）
- **コンテナ：** イメージのランタイムインスタンス、再作成/再起動されるまで元のイメージを使い続ける
- **重要な洞察：** `docker build`で`latest`タグを更新しても、実行中のコンテナには影響しない
- **解決策：** ビルド後にコンテナを自動再起動して新しいイメージの使用を強制

**4. Bash間接変数参照**
- 最初の試み：`${!key}` → "bad substitution"エラーで失敗
- **機能する解決策：** `eval echo "\${key}"`（より移植性が高い）
- **使用例：** `$key`に格納された名前で環境変数が存在するかをチェック

**5. 変更検出戦略**
- 現在のビルドと以前のビルド間で9つのインストールオプションを比較
- 成功後に状態を`~/monadic/log/python_build_options.txt`に保存
- オプションが異なる場合のみ`--no-cache`を使用（15-30分） vs 未変更の場合はキャッシュ（1-2分）
- **トレードオフ：** 信頼性（正しいパッケージ） vs 速度（高速再ビルド）
- **結果：** 両方の長所を実現

### テスト方法

**修正が正しく機能することを確認するには：**

1. **テスト1：LaTeXを有効化**
   ```bash
   # 設定でINSTALL_LATEX=trueに設定
   echo "INSTALL_LATEX=true" >> ~/monadic/config/env
   # Electronメニュー経由でビルド
   # 確認：dpkg -l | grep -i latex | wc -l → 100+であるべき
   ```

2. **テスト2：LaTeXを無効化**
   ```bash
   # INSTALL_LATEX=falseに設定
   echo "INSTALL_LATEX=false" >> ~/monadic/config/env
   # 再ビルド
   # 確認：dpkg -l | grep -i latex | wc -l → 0であるべき
   ```

3. **テスト3：変更なしの再ビルド**
   ```bash
   # オプションを変更せずに再ビルド
   # 表示されるべき："[INFO] Install options unchanged, using build cache"
   # ビルド時間は約1-2分であるべき
   ```

4. **テスト4：コンテナ自動再起動**
   ```bash
   # 任意のビルド後、コンテナ作成時刻を確認
   # ビルド完了から数秒以内であるべき
   docker ps --format "{{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | grep python
   ```

### 避けるべき一般的な落とし穴

1. **docker buildコマンドで`${cache_flag}`を引用符で囲まない**
   - ❌ 間違い：`docker build "${cache_flag}" ...`
   - ✅ 正しい：`docker build ${cache_flag} ...`
   - 理由：空の場合、引用符付きは`""`となり引数として扱われ、引用符なしは何もなくなる

2. **間接変数参照に`${!key}`を使用しない**
   - 一部のBashバージョンで"bad substitution"で失敗する可能性がある
   - 代わりに`eval echo "\${key}"`を使用

3. **`docker build`が実行中のコンテナを更新すると仮定しない**
   - 新しいイメージをビルドした後は常にコンテナを再起動または再作成
   - これは現在自動的に処理されている

4. **オプション変更検出をスキップしない**
   - オプション未変更の場合は常にパフォーマンスを節約
   - オプション変更時の信頼性を保証

## 関連ファイル

- `docker/monadic.sh`：ビルドロジックと変更検出（422-586行）
- `app/main.js`：Electronメニューと環境変数の受け渡し（2446-2469行）
- `~/monadic/config/env`：ユーザー設定ファイル
- `~/monadic/log/python_build_options.txt`：前回ビルドから保存されたオプション
- `docker/services/python/Dockerfile`：Pythonコンテナ定義

## 実装履歴

この機能は、LaTeX/CJKパッケージの欠落によりSyntax Treeアプリが画像を生成できなかったというユーザー報告問題に対応して開発されました。

**コミット：**
- `fc56c74a`：Syntax Treeプロンプトでブラケット表記形式を明確化
- `423ad8de`：Pythonコンテナビルドのスマートキャッシングを実装
- `618c5480`：ビルドキャッシング実装からデバッグ出力を削除
- `86d2bca6`：ビルド後にPythonコンテナを自動再起動して新イメージを使用

**元の問題：**
- ユーザーがElectronメニューで`INSTALL_LATEX=true`を設定し、「Build All」を実行
- Dockerfileにあるにもかかわらず、LaTeXパッケージがインストールされなかった
- 根本原因：環境変数の伝播 + Dockerキャッシュの動作

**開発プロセス：**
1. **調査**：`read_cfg_bool`が環境変数をチェックしていないことを発見
2. **最初の修正**：環境変数を最初にチェックするように`read_cfg_bool`を変更
3. **キャッシュ問題**：正しいenv varsがあってもDockerキャッシュがバイパスされた
4. **スマートキャッシング**：必要な場合のみ`--no-cache`を使用する変更検出を実装
5. **コンテナ問題**：実行中のコンテナが新しいイメージに自動更新されないことを発見
6. **最終修正**：ビルド成功後のコンテナ自動再起動を追加
7. **ドキュメント**：テスト方法を含む包括的なガイドを作成

**テストで確認済み：**
- ✅ LaTeXのオン/オフ切り替えが正しく機能
- ✅ 再ビルド後にコンテナが自動的に最新イメージを使用
- ✅ オプション未変更時の高速再ビルド（約1-2分）
- ✅ オプション変更時の完全再ビルド（約15-30分）
- ✅ Syntax Treeアプリが日本語構文木を正常に生成

## 関連項目

- [Dockerアーキテクチャ](docker-architecture.md)
- 開発ワークフロー：`docs_dev/developer/development_workflow.md`を参照
- Syntax Treeアプリ：`docs/apps/syntax_tree.md`を参照
