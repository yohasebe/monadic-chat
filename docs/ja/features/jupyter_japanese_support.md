# Jupyter Notebookの日本語テキストサポート

Monadic ChatのJupyter Notebookアプリケーションは、matplotlibプロットの自動日本語フォント設定を含むようになりました。

## 機能

### 自動フォント設定
以下を含むJupyter notebookを作成または実行すると：
- 日本語テキスト（ひらがな、カタカナ、または漢字）
- matplotlibのインポートまたは使用

システムは自動的にフォント設定セルを挿入します：
1. 日本語フォント（Noto Sans CJK JPまたはIPAGothic）を使用するようmatplotlibを設定
2. フォント関連の警告を抑制
3. プロット内の日本語文字の適切な表示を保証

### 動作の仕組み

フォント設定コードは自動的に挿入されます：
- 最初のmatplotlibインポート文の後（存在する場合）
- またはノートブックの先頭（インポートが見つからない場合）
- 日本語テキストまたはmatplotlibの使用が検出された場合のみ
- まだ存在しない場合のみ（「font-setup」メタデータでタグ付け）

### サポートされているフォント

システムは以下のフォントを順番にチェックします：
1. Noto Sans CJK JP（推奨）
2. IPA Gothic
3. システム設定の日本語フォント

### 例

日本語テキストを含むノートブックを作成すると：

```python
import matplotlib.pyplot as plt
import numpy as np

# 日本語ラベルを含むプロット
plt.plot([1, 2, 3], [1, 4, 2])
plt.title('日本語のタイトル')
plt.xlabel('横軸')
plt.ylabel('縦軸')
plt.show()
```

システムはコードが実行される前に自動的にフォント設定を追加し、日本語テキストが正しく表示されるようにします。

## 技術詳細

### フォントパス
システムは以下のフォントの場所をチェックします：
- `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`
- `/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc`
- `/usr/share/fonts/opentype/ipafont/ipag.ttf`
- `/usr/share/fonts/truetype/ipafont/ipag.ttf`

### 設定
- フォントファミリー: sans-serif
- Unicodeマイナス: 無効（マイナス記号の表示問題を防止）
- 警告: 欠落グリフに対して抑制

## トラブルシューティング

日本語テキストがまだ表示されない場合：
1. Jupyterカーネルを再起動
2. すべてのセルを再実行
3. フォント設定セルが正常に実行されたことを確認
4. Pythonコンテナにフォントがインストールされていることを確認

## 注意事項

- この機能はすべてのJupyter Notebookアプリ（OpenAI、Claude、Gemini、Grok）で利用可能
- フォント設定は各ノートブックセッション内で永続的
- 手動設定は不要 - 自動です！
