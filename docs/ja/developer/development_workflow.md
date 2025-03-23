# 開発ワークフロー

このドキュメントには、Monadic Chatプロジェクトに貢献する開発者向けのガイドラインと指示が含まれています。

## セットアップスクリプトの管理

`docker/services/python/`と`docker/services/ruby/`にある`pysetup.sh`と`rbsetup.sh`ファイルは、コンテナビルド中に追加パッケージをインストールするためにユーザーがカスタマイズできます。ローカルでビルドする場合、これらのファイルは`~/monadic/config/`ディレクトリからユーザー提供バージョンに置き換えられる可能性があります。

### 重要：コミット前にセットアップスクリプトをリセットする

バージョン管理の一貫性のために、常にこれらのスクリプトのオリジナルバージョンをコミットしたいと考えています。リポジトリに変更をコミットする前に、以下のいずれかの方法でこれらのファイルをリセットしてください：

#### 方法1：リセットスクリプトの使用

提供されたリセットスクリプトを実行します：

```bash
./docker/services/reset_setup_scripts.sh
```

これにより、セットアップスクリプトのオリジナルバージョンがgitから復元されます。

#### 方法2：手動リセット

あるいは、gitを使用して手動でファイルをリセットすることもできます：

```bash
git checkout -- docker/services/python/pysetup.sh docker/services/ruby/rbsetup.sh
```

### Gitプリコミットフック（オプション）

各コミット前に自動的にこれらのファイルをリセットするgitプリコミットフックを設定できます：

1. `.git/hooks/`ディレクトリに`pre-commit`という名前のファイルを作成します：

```bash
touch .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

2. プリコミットフックに以下の内容を追加します：

```bash
#!/bin/bash
# .git/hooks/pre-commit - コミット前に自動的にセットアップスクリプトをリセット

# コミット用にステージングされているファイルを取得
STAGED_FILES=$(git diff --cached --name-only)

# セットアップスクリプトが変更されているかチェック
if echo "$STAGED_FILES" | grep -q "docker/services/python/pysetup.sh\|docker/services/ruby/rbsetup.sh"; then
  echo "⚠️ コミット内でセットアップスクリプトの変更が検出されました。"
  echo "⚠️ gitからオリジナルバージョンにリセットしています..."
  
  # リセット
  git checkout -- docker/services/python/pysetup.sh
  git checkout -- docker/services/ruby/rbsetup.sh
  
  # ステージングに再追加
  git add docker/services/python/pysetup.sh
  git add docker/services/ruby/rbsetup.sh
  
  echo "✅ セットアップスクリプトがリセットされました。コミットを続行します。"
fi

# コミットを進める
exit 0
```

このプリコミットフックは、コミット前にセットアップスクリプトへの変更を自動的に検出してリセットします。

## ユーザー向け

コンテナをカスタマイズしたいユーザーは、以下の場所にカスタムスクリプトを配置する必要があります：
- Pythonのカスタマイズには`~/monadic/config/pysetup.sh`
- Rubyのカスタマイズには`~/monadic/config/rbsetup.sh`

これらはローカルでコンテナをビルドする際に自動的に使用されますが、リポジトリファイルには影響しません。

## 重複コンテナビルドの回避

Monadic Chatのビルドシステムは、不必要に複数回コンテナをビルドしないように最適化されています。最近の改善点は以下の通りです：

1. コンテナ固有のビルド関数における冗長な`build_docker_compose`呼び出しの削除
2. 必要な場合にのみ再ビルドするように`start_docker_compose`のロジックを改善
3. 再ビルドが必要な場合を追跡するためのブールフラグの使用

これらの変更により、重複したビルドを防ぎ、不要なチェックを削減することで、ビルドプロセスがより効率的になります。