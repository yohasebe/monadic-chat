# Monadic Chat開発者向けパスハンドリングガイド

## 概要

Monadic Chatは2つの異なる環境（ローカル開発とDocker本番）で動作するため、ファイルパス処理に複雑さが生じます。このガイドでは、パス抽象化システムと安全なファイル操作のベストプラクティスを説明します。

---

## 3つのタイプのパス

### 1. **ファイルシステムパス**（Ruby内部）

実際のファイルI/O操作に使用。

- **開発環境**：`/Users/username/monadic/data/file.txt`
- **本番環境**：`/monadic/data/file.txt`（Dockerコンテナ内）

**使用方法：**
```ruby
data_dir = Monadic::Utils::Environment.data_path
file_path = File.join(data_dir, "report.pdf")
File.read(file_path)
```

### 2. **Web URLパス**（HTML/フロントエンド）

ブラウザからファイルにアクセスするためにHTMLで使用。

- **両環境**：`/data/file.txt`

**使用方法：**
```ruby
# AIがWebパス付きのHTMLを生成
"<img src='/data/chart.png' />"
"<a href='/data/subdir/report.pdf'>ダウンロード</a>"
```

### 3. **AIプロンプトパス**（システムプロンプト）

AIにファイルの場所を指示する際に使用。

- **相対パス**：`"file.txt"`または`"subdir/file.txt"`
- **ユーザーフレンドリー**：`"the shared folder"`

**システムプロンプトの例：**
```markdown
生成された画像をファイル名のみを使用して共有フォルダに保存してください。
次のように表示：<img src="/data/FILENAME" />
```

---

## Environment モジュール

### コア抽象化

`Monadic::Utils::Environment`は環境を認識したパス解決を提供します。

```ruby
module Monadic::Utils::Environment
  # Docker内で実行されているかを検出
  def in_container?
    ENV['IN_CONTAINER'] == 'true' || File.file?("/.dockerenv")
  end

  # 環境に基づいてパスを解決
  def resolve_path(container_path, local_path = nil)
    if in_container?
      container_path
    else
      local_path || container_path.sub('/monadic', File.join(Dir.home, 'monadic'))
    end
  end

  # 標準パス
  def data_path
    resolve_path('/monadic/data')
  end
end
```

### 利用可能なメソッド

| メソッド | 開発環境 | 本番環境 | 目的 |
|--------|-------------|------------|---------|
| `data_path` | `~/monadic/data` | `/monadic/data` | 共有フォルダ |
| `config_path` | `~/monadic/config` | `/monadic/config` | 設定 |
| `log_path` | `~/monadic/log` | `/monadic/log` | ログファイル |
| `scripts_path` | `~/monadic/data/scripts` | `/monadic/data/scripts` | ユーザースクリプト |
| `apps_path` | `~/monadic/data/apps` | `/monadic/data/apps` | カスタムアプリ |

---

## パス検証

### `validate_file_path` メソッド

**場所：** `lib/monadic/adapters/read_write_helper.rb`

**目的：** ディレクトリトラバーサル攻撃を防ぎ、ファイルが共有フォルダ内にあることを確認します。

**戻り値：**
- **成功**：検証されたパスを返す（文字列）
- **失敗**：エラー詳細を含むハッシュを返す

```ruby
validation_result = validate_file_path(file_path)

if validation_result.is_a?(Hash)
  # 検証失敗
  return "Error: #{validation_result[:error]}"
end

# 検証成功、ファイル操作を続行
File.read(file_path)
```

**エラーハッシュ構造：**
```ruby
{
  error: "Path traversal not allowed",
  path: "../../etc/passwd",
  resolved_path: "/etc/passwd",
  allowed_directory: "/monadic/data"
}
```

### セキュリティ機能

1. **パストラバーサル防止**：`..`シーケンスをブロック
2. **シンボリックリンク解決**：`File.realpath`を使用してシンボリックリンクを解決
3. **境界チェック**：解決されたパスが`data_path`内にあることを確認
4. **詳細なエラー**：失敗ケースでデバッグ情報を提供

---

## ベストプラクティス

### ✅ すべきこと：常にEnvironmentモジュールを使用

```ruby
# 良い
data_dir = Monadic::Utils::Environment.data_path
file_path = File.join(data_dir, filename)

# 悪い - ハードコードされたパス
file_path = "/monadic/data/#{filename}"
```

### ✅ すべきこと：ファイル操作前に検証

```ruby
def read_file_from_shared_folder(filepath:)
  data_dir = Monadic::Utils::Environment.data_path
  full_path = File.join(data_dir, filepath)

  # 常に最初に検証
  validation_result = validate_file_path(full_path)
  if validation_result.is_a?(Hash)
    return "Error: #{validation_result[:error]}"
  end

  # 安全に続行
  File.read(full_path)
end
```

### ✅ すべきこと：サブディレクトリをサポート

```ruby
# 良い - "projects/report.pdf"をサポート
full_path = File.join(data_dir, filepath)

# 悪い - ルートレベルのみサポート
full_path = File.join(data_dir, File.basename(filepath))
```

### ✅ すべきこと：HTMLでWebパスを使用

```ruby
# 良い - 両環境で動作
"<img src='/data/chart.png' />"

# 悪い - 環境固有
"<img src='#{data_dir}/chart.png' />"
```

### ❌ すべきでないこと：検証をスキップ

```ruby
# 悪い - 検証なし
def write_file(filepath:, content:)
  File.write(filepath, content)  # 安全でない！
end
```

### ❌ すべきでないこと：セキュリティのためにFile.basenameを使用

```ruby
# 悪い - サブディレクトリアクセスを防ぐ
safe_name = File.basename(file_name)
file_path = File.join(data_dir, safe_name)

# 良い - 代わりに検証
file_path = File.join(data_dir, file_name)
validation_result = validate_file_path(file_path)
```

---

## Webファイル配信

### Sinatraルート：`/data/:file_name`

**場所：** `lib/monadic.rb`

**機能：**
- HTTP経由で共有フォルダからファイルを配信
- サブディレクトリをサポート（例：`/data/projects/report.pdf`）
- トラバーサル攻撃を防ぐためにパスを検証

**実装：**
```ruby
get "/data/:file_name" do
  fetch_file(params[:file_name])
end

def fetch_file(file_name)
  datadir = Monadic::Utils::Environment.data_path

  # パスを正規化して分割
  path_parts = file_name.split('/').reject { |p| p.empty? || p == '.' }

  # パストラバーサルを拒否
  if path_parts.any? { |part| part == '..' }
    status 403
    return "Access denied: path traversal not allowed"
  end

  # パスを構築して検証
  file_path = File.join(datadir, *path_parts)
  real_path = File.realpath(file_path)
  real_datadir = File.realpath(datadir)

  # 許可されたディレクトリ内であることを確認
  if real_path.start_with?(real_datadir + File::SEPARATOR) && File.file?(real_path)
    send_file file_path
  else
    status 403
    "Access denied"
  end
end
```

**セキュリティ機能：**
1. パスコンポーネント内の`..`を拒否
2. `realpath`でシンボリックリンクを解決
3. 最終パスがデータディレクトリ内にあることを確認
4. ターゲットがファイルであることを確認（ディレクトリではない）

---

## 一般的なパターン

### パターン1：ユーザーファイルの読み取り

```ruby
def read_file_from_shared_folder(filepath:)
  data_dir = Monadic::Utils::Environment.data_path

  # 絶対パスと相対パスの両方をサポート
  full_path = if filepath.start_with?('/')
                filepath
              else
                File.join(data_dir, filepath)
              end

  # 検証
  validation_result = validate_file_path(full_path)
  if validation_result.is_a?(Hash)
    return "Error: #{validation_result[:error]}"
  end

  # 存在をチェック
  unless File.exist?(full_path)
    return "Error: File not found"
  end

  # 安全に読み取り
  File.read(full_path)
rescue StandardError => e
  "Error: #{e.message}"
end
```

### パターン2：ユーザーファイルの書き込み

```ruby
def write_file_to_shared_folder(filename:, content:)
  data_dir = Monadic::Utils::Environment.data_path
  full_path = File.join(data_dir, filename)

  # 検証
  validation_result = validate_file_path(full_path)
  if validation_result.is_a?(Hash)
    return "Error: #{validation_result[:error]}"
  end

  # ディレクトリが存在することを確認
  dir = File.dirname(full_path)
  FileUtils.mkdir_p(dir) unless File.directory?(dir)

  # 安全に書き込み
  File.write(full_path, content)

  "File saved: #{filename}"
rescue StandardError => e
  "Error: #{e.message}"
end
```

### パターン3：AI用のファイル生成

```ruby
def generate_chart(data:)
  timestamp = Time.now.to_i
  filename = "chart_#{timestamp}.png"

  data_dir = Monadic::Utils::Environment.data_path
  file_path = File.join(data_dir, filename)

  # 検証
  validation_result = validate_file_path(file_path)
  if validation_result.is_a?(Hash)
    return "Error: #{validation_result[:error]}"
  end

  # チャートを生成
  create_chart(data, file_path)

  # Webパス付きのHTMLを返す
  "<img src='/data/#{filename}' />"
end
```

---

## テスト

### ユニットテスト

Environmentモジュールをモック：

```ruby
RSpec.describe MyApp do
  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
  end

  it "validates file paths" do
    result = app.read_file("test.txt")
    expect(result).not_to include("Error")
  end
end
```

### 統合テスト

実際のパスでテスト：

```ruby
RSpec.describe "File operations", :integration do
  let(:data_dir) { Monadic::Utils::Environment.data_path }

  it "reads files from shared folder" do
    test_file = File.join(data_dir, "test.txt")
    File.write(test_file, "test content")

    result = app.read_file("test.txt")
    expect(result).to eq("test content")
  ensure
    File.delete(test_file) if File.exist?(test_file)
  end
end
```

---

## 移行チェックリスト

既存のコードを更新する際：

- [ ] ハードコードされた`/monadic/data`を`Environment.data_path`に置換
- [ ] すべてのファイル操作前に`validate_file_path`呼び出しを追加
- [ ] ハッシュ戻り値をチェックするようにエラーハンドリングを更新
- [ ] サブディレクトリをサポート（セキュリティのために`File.basename`を使用しない）
- [ ] HTML出力で`/data/`プレフィックスを使用
- [ ] 開発環境とDocker環境の両方でテスト
- [ ] パス検証のユニットテストを追加
- [ ] システムプロンプトを相対パスを使用するように更新

---

## デバッグ

### デバッグログを有効化

```ruby
DebugHelper.debug("File operation: #{file_path}", category: :api, level: :debug)
```

### 環境をチェック

```ruby
puts "In container: #{Monadic::Utils::Environment.in_container?}"
puts "Data path: #{Monadic::Utils::Environment.data_path}"
```

### 手動で検証

```ruby
result = validate_file_path(file_path)
if result.is_a?(Hash)
  pp result  # エラー詳細をプリティプリント
end
```

---

## サマリー

| 観点 | 開発環境 | 本番環境 | ベストプラクティス |
|--------|-------------|------------|---------------|
| ファイルI/O | `~/monadic/data/file.txt` | `/monadic/data/file.txt` | `Environment.data_path`を使用 |
| Web URL | `/data/file.txt` | `/data/file.txt` | 常に`/data/`プレフィックスを使用 |
| 検証 | 必須 | 必須 | `validate_file_path`を使用 |
| サブディレクトリ | サポート | サポート | `File.basename`を使用しない |
| セキュリティ | パストラバーサル保護 | パストラバーサル保護 | 操作前に検証 |

**重要なポイント：** 安全で環境に依存しないファイル操作のために、常に`Environment.data_path`と`validate_file_path`を使用してください。
