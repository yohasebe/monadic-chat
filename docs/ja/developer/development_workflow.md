# 開発ワークフロー

このドキュメントには、Monadic Chatプロジェクトに貢献する開発者向けのガイドラインと指示が含まれています。

?> このドキュメントは、Monadic Chat のレシピファイルの開発者ではなく、Monadic Chat自体の開発者向けです。

## テスト

### テストフレームワーク
- **JavaScript**: フロントエンドコードのテストにJestを使用
- **Ruby**: バックエンドコードのテストにRSpecを使用

### テスト構造
- JavaScriptテストは `test/frontend/` に配置
- Rubyテストは `docker/services/ruby/spec/` に配置
- Jestの設定は `jest.config.js` に定義
- JavaScriptのグローバルテスト設定は `test/setup.js` に定義

### テスト実行方法
#### Rubyテスト
```bash
rake spec
```

#### JavaScriptテスト
```bash
rake jstest        # 成功するJavaScriptテストを実行
npm test           # 上記と同じ
rake jstest_all    # すべてのJavaScriptテストを実行
npm run test:watch # ウォッチモードでテストを実行
npm run test:coverage # カバレッジレポート付きでテストを実行
```

#### すべてのテスト
```bash
rake test  # RubyとJavaScriptの両方のテストを実行
```
## 重要：セットアップスクリプトの管理

`docker/services/python/`と`docker/services/ruby/`にある`pysetup.sh`と`rbsetup.sh`ファイルは、コンテナビルド中、追加パッケージをインストールするためにユーザーが共有フォルダの`config`ディレクトリに配置したものに置き換えられます。バージョン管理システム（Git）には、常にこれらのスクリプトのオリジナルバージョンをコミットする必要があります。リポジトリに変更をコミットする前に、以下のいずれかの方法でこれらのファイルをリセットします。

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

