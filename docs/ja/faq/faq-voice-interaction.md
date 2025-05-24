# FAQ：音声入力と音声合成

**Q**: AIエージェントと音声による会話を行うことはできますか？

**A**: はい、可能です。Webインターフェイスの`Chat Interaction Controls`で`Auto speech`と`Easy submit`を両方有効にしてください。音声メッセージの入力開始と入力完了を（ボタンをクリックすることなく）Enterキーの打鍵で行うことができます。また、入力完了時にメッセージが自動的に送信され、AIエージェントからのレスポンスの合成音声が再生されます。つまり、タイミングよくエンターキーを押すだけで、AIエージェントと音声による会話を行うことができます。

---

**Q**: OpenAIやElevenLabsのAPIキーなしでテキスト読み上げ（TTS）を使用できますか？

**A**: はい、Text-to-Speech Providerドロップダウンで「Web Speech API」オプションを使用できます。これはブラウザの内蔵音声合成機能を使用し、APIキーは必要ありません。利用可能な声はオペレーティングシステムとブラウザに依存しますが、ほとんどの最新ブラウザはこの機能をサポートしています。

---

**Q**: Web Speech APIをテキスト読み上げに使用する場合、どのように声を選択しますか？

**A**: Text-to-Speech Providerで「Web Speech API」を選択すると、システムで利用可能なすべての声を表示するドロップダウンメニューが表示されます。これらの声はオペレーティングシステムとブラウザによって提供されます。異なるオペレーティングシステム（Windows、macOS、Linux）では、異なる声のオプションが利用可能です。

---

**Q**: どの音声認識モデルが利用可能で、どのように選択しますか？

**A**: Monadic Chatは複数のOpenAI音声認識モデル（「whisper-1」、「gpt-4o-mini-transcribe」、「gpt-4o-transcribe」）をサポートしています。設定パネルのSTT_MODELオプションで希望のモデルを選択できます。新しいモデル（gpt-4o-mini-transcribe、gpt-4o-transcribe）は、一般的に精度と文字起こし品質が向上しています。Monadic Chatは選択したモデルに基づいて音声フォーマットを自動的に最適化します。

---

**Q**: AIエージェントの音声の速度を調整することはできますか？

**A**: はい、音声設定パネルの`Text-to-Speech Speed`スライダーを使って、合成音声の再生速度を調整できます。速度は0.7（遅い）から1.2（速い）の範囲で調整可能です。ElevenLabsの音声は、OpenAIの音声と比較して、変更された速度でテキストを再生する際の品質が一般的に優れています。Web Speech APIも速度調整をサポートしていますが、品質はブラウザやオペレーティングシステムによって異なる場合があります。

---

**Q**: Gemini TTSとは何ですか？他のプロバイダーとの違いは？

**A**: Gemini TTSはGoogleのテキスト読み上げサービスで、2つのモデルを提供しています：Gemini Flash TTS（より高速、gemini-2.5-flash-preview-ttsを使用）とGemini Pro TTS（より高品質、gemini-2.5-pro-preview-ttsを使用）。両モデルとも8つのユニークな音声（Aoede、Charon、Fenrir、Kore、Orus、Puck、Schedar、Zephyr）を提供し、自然な音声合成を実現します。Gemini TTSはGemini APIキーが必要で、対話型会話用のリアルタイムストリーミングとSpeech Draft Helperアプリを通じたMP3ファイル生成の両方をサポートしています。

---

**Q**: 音声合成の際に実際の言語とは異なる言語で再生されることがあります。どうすればいいですか？

**A**: Webインターフェイスの`Speech-to-Text (STT) Language`セレクタはデフォルトでは`Automatic`になっています。これを特定の言語に設定することで、音声合成の際に指定した言語で再生されるようになります。

---

**Q**: 入力テキストを音声合成してMP3ファイルとして保存することはできますか？

**A**: はい、`Speech Draft Helper`アプリを選択して、テキストを入力した上で、MP3ファイルに変換するようにAIエージェントに指示することで、音声合成した結果をファイルとして保存することができます。Speech Draft HelperはOpenAI、ElevenLabs、Gemini（gemini-2.5-flash-preview-ttsモデルを使用）を含む複数のTTSプロバイダーをサポートしており、MP3生成時に異なる音声とプロバイダーを選択できます。

