# FAQ：音声入力と音声合成

**Q**: AIエージェントと音声による会話を行うことはできますか？ :id=voice-conversation

**A**: はい、可能です。Webインターフェイスの`Chat Interaction Controls`で`Auto speech`と`Easy submit`を両方有効にしてください。音声メッセージの入力開始と入力完了を（ボタンをクリックすることなく）Enterキーの打鍵で行うことができます。また、入力完了時にメッセージが自動的に送信され、AIエージェントからのレスポンスの合成音声が再生されます。つまり、タイミングよくエンターキーを押すだけで、AIエージェントと音声による会話を行うことができます。

---

**Q**: OpenAIやElevenLabsのAPIキーなしでテキスト読み上げ（TTS）を使用できますか？ :id=tts-without-api-key

**A**: はい、Text-to-Speech Providerドロップダウンで「Web Speech API」オプションを使用できます。これはブラウザの内蔵音声合成機能を使用し、APIキーは必要ありません。利用可能な声はオペレーティングシステムとブラウザに依存しますが、ほとんどの最新ブラウザはこの機能をサポートしています。

---

**Q**: Web Speech APIをテキスト読み上げに使用する場合、どのように声を選択しますか？ :id=web-speech-api-voices

**A**: Text-to-Speech Providerで「Web Speech API」を選択すると、システムで利用可能なすべての声を表示するドロップダウンメニューが表示されます。これらの声はオペレーティングシステムとブラウザによって提供されます。異なるオペレーティングシステム（Windows、macOS、Linux）では、異なる声のオプションが利用可能です。

---

**Q**: どの音声認識モデルが利用可能で、どのように選択しますか？ :id=stt-model-selection

**A**: Monadic Chatは複数のOpenAI音声認識モデル（「whisper-1」、「gpt-4o-mini-transcribe」、「gpt-4o-transcribe」）をサポートしています。設定パネルのSTT_MODELオプションで希望のモデルを選択できます。新しいモデル（gpt-4o-mini-transcribe、gpt-4o-transcribe）は、一般的に精度と文字起こし品質が向上しています。Monadic Chatは選択したモデルに基づいて音声フォーマットを自動的に最適化します。

---

**Q**: AIエージェントの音声の速度を調整することはできますか？ :id=voice-speed-adjustment

**A**: はい、音声設定パネルの`Text-to-Speech Speed`スライダーを使って、合成音声の再生速度を調整できます。速度は0.7（遅い）から1.2（速い）の範囲で調整可能です。ElevenLabsの音声は、OpenAIの音声と比較して、変更された速度でテキストを再生する際の品質が一般的に優れています。Web Speech APIも速度調整をサポートしていますが、品質はブラウザやオペレーティングシステムによって異なる場合があります。

---

**Q**: Gemini TTSとは何ですか？他のプロバイダーとの違いは？ :id=gemini-tts-overview

**A**: Gemini TTSはGoogleのテキスト読み上げサービスで、gemini-2.5-flash-preview-ttsモデルを使用します。8つのユニークな音声（Aoede、Charon、Fenrir、Kore、Orus、Puck、Schedar、Zephyr）を提供し、自然な音声合成を実現します。Gemini TTSはGemini APIキーが必要で、対話型会話用のリアルタイムストリーミングとSpeech Draft Helperアプリを通じたオーディオファイル生成（WAVフォーマット）の両方をサポートしています。

---

**Q**: 音声合成の際に実際の言語とは異なる言語で再生されることがあります。どうすればいいですか？ :id=tts-language-detection

**A**: TTS（テキスト読み上げ）システムはテキストの言語を自動的に検出して、それに応じた音声合成を行います。言語検出が正しくない場合は、通常、テキストに複数の言語が混在していたり、内容が曖昧だったりすることが原因です。正しい発音を確保するには、テキストを単一の言語で記述するようにしてください。なお、`Speech-to-Text (STT) Language`設定は音声認識の入力にのみ影響し、TTS出力には影響しません。

---

**Q**: 入力テキストを音声合成してオーディオファイルとして保存することはできますか？ :id=saving-audio-files

**A**: はい、`Speech Draft Helper`アプリを選択して、テキストを入力した上で、オーディオファイルに変換するようにAIエージェントに指示することで、音声合成した結果をファイルとして保存することができます。Speech Draft Helperは複数のTTSプロバイダーをサポートしています：OpenAIとElevenLabsはMP3ファイルを出力し、GeminiはWAVファイルを出力します。オーディオ生成時に異なる音声とプロバイダーを選択できます。

