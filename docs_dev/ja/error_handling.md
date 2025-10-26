# エラーハンドリングアーキテクチャ

このノートは、長時間実行されるエージェントセッションを回復可能に保つランタイムセーフガードをまとめたものです。リトライや予期しない停止をデバッグする際のマップとして使用してください。

## ErrorPatternDetector
- ファイル：`docker/services/ruby/lib/monadic/utils/error_pattern_detector.rb`
- セッションごとの最近のツールエラーを追跡し、一般的な失敗を分類（フォント、欠落モジュール、権限、リソース、プロット、ファイルI/O、ネットワーク）。
- 3回類似したエラーが発生すると、検出器はリトライを停止すべきというシグナルを送り、次のステップをまとめたユーザー向け提案ブロックを返します。
- 履歴は最後の10エントリに制限されます。仕様は停止条件を検証するために合成エラーを注入できます。

## FunctionCallErrorHandler
- ベンダーヘルパー（OpenAI、Claude、Gemini）によって消費され、ツールレスポンスを検出器に接続するMixin。
- `handle_function_error`は失敗を記録し、緩和ガイダンスを含むフラグメントを発行し、検出器が停止を要求したときに`session[:parameters]["stop_retrying"]`を設定します。
- `reset_error_tracking(session)`は新しい会話のために状態をクリアします。デバッグ中にセッションを手動で巻き戻す際に呼び出します。

## NetworkErrorHandler
- 指数バックオフ（`with_network_retry`）で送信HTTP呼び出しをラップします。
- プロバイダー固有のタイムアウトオーバーライド（`PROVIDER_TIMEOUTS`）は、ClaudeやDeepSeekなどの遅いAPIをガードします。
- `format_network_error`は低レベル例外をユーザーフレンドリーなメッセージにマッピングします。リトライが尽きると、フォーマットされたテキストを持つ`RuntimeError`が表面化するため、UIコピーはここで一元化されます。

## 実用的なチェックリスト
- 「スタック」したツールを調査する際は、`session[:error_patterns]`をダンプして、どのパターンが一致したか、`stop_retrying`が設定されているかを確認します。
- 新しいアダプターで`with_network_retry`をバイパスしないでください：レイテンシスパイクが繰り返しツール失敗にカスケードするのを防ぎます。
- 新しいエラークラスには、`SYSTEM_ERROR_PATTERNS`を拡張し、提案文字列を更新します。トーンはアクション志向で簡潔に保ちます。

## 関数呼び出し深度制限（MAX_FUNC_CALLS）
- 定数: OpenAI helperで`MAX_FUNC_CALLS = 20`
- 目的: AIが1つのレスポンス内で再帰的にツールを呼び出す際の無限ループを防止
- スコープ: **ユーザーターンごと**（`role == "user"`の時にリセット）
- 追跡: パラメータの累積ではなく`session[:call_depth_per_turn]`を使用
- 動作:
  - 各ユーザーメッセージでカウンターを0にリセット
  - レスポンス内のツール呼び出しがカウンターをインクリメント
  - 1ターン内でカウンターが20を超えると「最大関数呼び出し深度を超えました」通知を表示
  - ユーザーによる反復は無制限に許可（Image Generatorなどの反復アプリにとって重要）

### 歴史的注記（2024年10月）
2024年10月以前は、`call_depth`が会話セッション全体で累積され、反復的な改良アプリ（例：Image Generator）が合計20回の対話後に失敗していました。修正により、スコープをユーザーターンごとに変更し、各新しいユーザーメッセージがカウンターをリセットしながら、1つのレスポンス内での暴走ツール呼び出しに対する保護を維持するようになりました。

## 関連テスト
- `spec/unit/utils/error_pattern_detector_spec.rb`
- `spec/unit/utils/function_call_error_handler_spec.rb`
- `spec/unit/utils/network_error_handler_spec.rb`

これらの仕様は実行可能なドキュメントとしても機能します。リトライしきい値やカテゴリを変更する前にざっと目を通してください。
