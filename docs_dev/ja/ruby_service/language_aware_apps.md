# アプリによる言語設定認識

## 言語セレクター設定を使用するアプリ

これらのアプリは、言語セレクターからのユーザーの言語設定を尊重します：

### 標準チャットアプリ
- Chat（すべてのプロバイダー）
- Chat Plus（すべてのプロバイダー）
- Coding Assistant
- Content Reader
- Research Assistant
- Second Opinion
- Math Tutor
- Mail Composer
- Novel Writer
- Speech Draft Helper
- Monadic Help
- PDF Navigator

### クリエイティブアプリ
- Image Generator
- Video Generator
- DrawIO Grapher
- Concept Visualizer
- Syntax Tree

### コード関連アプリ
- Code Interpreter
- Jupyter Notebook

## 部分的に言語セレクターをサポートするアプリ

これらのアプリは、初期インタラクションでは言語セレクターを尊重しますが、コア機能には独自の言語管理があります：

### 翻訳・言語学習アプリ
- **Voice Interpreter** - 初期質問にユーザーの言語を使用し、その後翻訳言語を管理
- **Translate** - ユーザーの言語を使用してソース/ターゲット言語を尋ねる
- **Language Practice** - 初期挨拶と学習目標に関する質問にユーザーの言語を使用
- **Language Practice Plus** - Language Practiceに類似した拡張機能付き

### これらのアプリが言語設定を使用する方法

これらのアプリは、言語学習と翻訳のために特別に設計されています：
1. **初期インタラクション** - 挨拶とセットアップの質問にユーザーの優先言語を使用
2. **コア機能** - 主要な目的の一部として言語を独立して管理
3. **説明** - ヘルプや説明を提供する際にユーザーの優先言語にフォールバック
4. **複数言語** - 学習/翻訳のための異なる言語の同時使用をサポート

## 推奨事項

翻訳・言語学習アプリの場合：
- アプリは初期インタラクションに言語セレクターを使用（UX改善）
- コア機能は言語を独立して管理（必要に応じて）
- このハイブリッドアプローチにより、機能を維持しながら優れたユーザーエクスペリエンスを提供

その他のアプリの場合：
- すべての標準会話アプリは言語セレクターを正しく使用
- 言語設定はシステムプロンプトに適切に注入される
- RTL言語はUI内で適切に処理される
