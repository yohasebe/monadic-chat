# ドキュメントリンクチェッカー

## 概要

ドキュメントリンクチェッカーは、`docs/` および `docs_dev/` ディレクトリ内のすべての内部リンクを検証し、それらが実際に存在するファイルを指していることを確認するlintツールです。

## 目的

- ドキュメント内のリンク切れを防止
- 欠落しているファイルや不正なパスを自動検出
- コードベースの進化に伴うドキュメント品質の維持

## 使い方

### チェッカーの実行

```bash
# npmスクリプトを使用（推奨）
npm run lint:docs-links

# または直接実行
ruby scripts/lint/check_docs_links.rb
```

### 終了コード

- `0`: すべてのリンクが有効
- `1`: リンク切れが見つかった

## チェック対象

以下を検証します：

✅ **内部マークダウンリンク** - `[text](path/to/sample-file.md)`
✅ **相対パス** - `../other-dir/sample-file.md`
✅ **絶対パス** - `/path/from/docs/sample-root.md`
✅ **ディレクトリリンク** - `frontend/` （`frontend/README.md`を期待）
✅ **.md拡張子なしのリンク** - 自動的に`.md`拡張子を試行
✅ **アンカー付きリンク** - `sample-file.md#section` （ファイルの存在を検証）

## スキップするもの

以下は無視されます：

🔸 **外部リンク** - `http://`, `https://`, `ftp://`
🔸 **メールアドレス** - `name@example.com`
🔸 **アンカーのみのリンク** - `#section-name`
🔸 **サンプルリンク** - `sample`キーワードを含むリンク（例：`sample-file.md`）
🔸 **Docsifyのサイズ記法** - 検証前に`:size=40`を削除
🔸 **コードブロック** - ` ``` ` フェンス付きコードブロック内のリンク

## 動作の仕組み

1. **すべてのマークダウンファイルをスキャン** （`docs/`および`docs_dev/`内）
2. **リンクを抽出** - 正規表現パターン`\[text\](url)`を使用
3. **パスを解決** - 以下を考慮：
   - 現在のファイルの位置（相対パスの場合）
   - ドキュメントルート（絶対パスの場合）
   - 日本語版のパス（`/ja/`）
4. **ファイルの存在を確認**して違反を報告

## パス解決の例

### 絶対パス
```markdown
<!-- docs/README.md内 -->
[Link](/advanced-topics/sample-foo.md)
→ 解決先: docs/advanced-topics/sample-foo.md

<!-- docs_dev/ja/README.md内 -->
[Link](/ja/frontend/)
→ 解決先: docs_dev/ja/frontend/README.md
```

### 相対パス
```markdown
<!-- docs/advanced-topics/sample-foo.md内 -->
[Link](../getting-started/sample-bar.md)
→ 解決先: docs/getting-started/sample-bar.md

<!-- docs_dev/ruby_service/README.md内 -->
[Link](testing/sample-overview.md)
→ 解決先: docs_dev/ruby_service/testing/sample-overview.md
```

### ディレクトリリンク
```markdown
[Frontend](frontend/)
→ 確認対象: frontend/README.md
```

## よくある問題と修正方法

### 問題: 存在しないファイルへのリンク

**エラー:**
```
docs/README.md:15
  Link: [Foo](advanced-topics/foo.md)
  Resolved to: docs/advanced-topics/foo.md
  Error: Link target does not exist
```

**修正方法:**
- 欠落しているファイルを作成、または
- リンクを削除/更新

### 問題: 誤ったパス形式

**エラー:**
```
docs_dev/ja/README.md:20
  Link: [Test](../test.md)
  Resolved to: docs_dev/test.md
  Error: Link target does not exist
```

**修正方法:**
- 絶対パスを使用: `[Test](/ja/sample-test.md)`
- または欠落している翻訳を作成

### 問題: READMEのないディレクトリ

**エラー:**
```
docs_dev/frontend/README.md:10
  Link: [Components](sample-components/)
  Resolved to: docs_dev/frontend/sample-components/README.md
  Error: Link target does not exist
```

**修正方法:**
- `sample-components/README.md`を作成、または
- 代わりに特定のファイルにリンク

## CI/CDへの統合

Monadic Chatは現在CIを使用していませんが、このチェッカーは以下に統合できます：

- **プレコミットフック** - コミット前にリンクを検証
- **GitHub Actions** - プルリクエストで実行
- **ローカル開発** - ドキュメントワークフローの一部として

## 技術詳細

- **スクリプトの場所**: `scripts/lint/check_docs_links.rb`
- **言語**: Ruby（パス処理にPathnameを使用）
- **依存関係**: なし（Ruby標準ライブラリを使用）
- **パフォーマンス**: 高速（約100ファイルで約1秒）

## チェッカーのメンテナンス

### 新しいリンクパターンの追加

`check_docs_links.rb`の`LINK_PATTERN`を編集：
```ruby
LINK_PATTERN = /\[([^\]]+)\]\(([^)]+)\)/
```

### 特定のパターンを無視

`external_link?()`メソッドに追加：
```ruby
def external_link?(url)
  url.start_with?('http://', 'https://') ||
    url.match?(/your-pattern-here/)
end
```

### 対象ディレクトリの変更

`DOCS_DIRS`配列を変更：
```ruby
DOCS_DIRS = [ROOT.join('docs'), ROOT.join('docs_dev')]
```

## 関連項目

- [デバッグモードとローカルドキュメント](server-debug-mode.md) - ドキュメントをローカルで表示する方法
- [よくある問題](common-issues.md) - トラブルシューティングガイド
