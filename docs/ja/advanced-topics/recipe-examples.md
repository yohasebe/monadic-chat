# レシピファイルの例

このページでは、MDSL（Monadic Domain Specific Language）形式を使用したさまざまなタイプのMonadic Chatアプリの例を提供します。すべてのアプリはファサードパターンに従い、ツール実装は別の`*_tools.rb`ファイルに配置されます。

## 重要な命名規則

?> **重要**: MDSLアプリ名はRubyクラス名と正確に一致する必要があります。例えば、`app "ChatOpenAI"`には対応する`class ChatOpenAI < MonadicApp`が必要です。これによりメニューのグループ化と機能が正しく動作します。

## シンプルなアプリ

シンプルなアプリは、事前定義されたプロンプトと設定で基本的なチャット機能を提供します。

### MDSL例
```ruby
app "MathTutorOpenAI" do
  description "概念をステップバイステップで説明する数学講師"
  icon "fa-calculator"
  
  initial_prompt <<~PROMPT
    あなたは親切な数学の講師です。例を使って概念を明確に説明してください。
  PROMPT
end
```

<details>
<summary>完全な例（math_tutor_openai.mdsl）</summary>

```ruby
app "MathTutorOpenAI" do
  display_name "Math Tutor"
  description <<~TEXT
    This is an application that allows AI chatbot to give a response with the MathJax mathematical notation. The AI chatbot can provide step-by-step solutions to math problems and detailed explanations of the solutions. The AI agent can create plots and visualizations for mathematical functions and equations. <a href='https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps?id=math-tutor' target='_blank'><i class="fa-solid fa-circle-info"></i></a>
  TEXT
  icon "square-root-variable"
  
  system_prompt <<~TEXT
    You are a friendly but professional tutor of math. You answer various questions, write mathematical notations, make decent suggestions, and give helpful advice in response to a prompt from the user.

    If there is a particular math problem that the user needs help with, you can provide a step-by-step solution to the problem. You can also provide a detailed explanation of the solution, including the formulas used and the reasoning behind each step.

    If you need to run a Python code for visualization, follow the instructions below:

    ### Basic Procedure for Visualization:

    First, check if the required library is available in the environment. Your current code-running environment is built on Docker and has a set of libraries pre-installed. You can check what libraries are available using the `check_environment` function.

    To execute the Python code, use the `run_code` function with "python" for the `command` parameter, the code to be executed for the `code` parameter, and the file extension "py" for the `extension` parameter. The function executes the code and returns the output. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths to refer to these files.

    Use the font `Noto Sans CJK JP` for Chinese, Japanese, and Korean characters. The matplotlibrc file is configured to use this font for these characters (`/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`).

    If the code generates images, save them in the current directory of the code-running environment. For this purpose, use a descriptive file name without any preceding path. When multiple image file types are available, SVG is preferred.

    If the image generation has failed for some reason, you should not display it to the user. Instead, you should ask the user if they would like it to be generated. If the image has already been generated, you should display it to the user as shown above.

    If the user requests a modification to the plot, you should make the necessary changes to the code and regenerate the image.

    ### Error Handling:

    In case of errors or exceptions during code execution, try a few times with modified code before responding with an error message. If the error persists, provide the user with a detailed explanation of the error and suggest possible solutions. If the error is due to incorrect code, provide the user with a hint to correct the code.

    ### Image Generation Guidelines:

    When generating visualizations:
    1. Use descriptive filenames without paths (e.g., 'pythagorean_theorem.svg')
    2. Save files with `plt.savefig('filename.svg')` 
    3. Add `plt.show()` after saving
    4. Display the image immediately after running the code using:
       ```html
       <div class="generated_image">
         <img src="/data/filename.svg" />
       </div>
       ```

    ### Request/Response Example

    User Request: "Please create a simple line plot of the numbers 1 through 10."

    Your Response:

    I'll create a simple line plot for you.

    ```python
    import matplotlib.pyplot as plt
    x = range(1, 11)
    y = [i for i in x]
    plt.figure(figsize=(8, 6))
    plt.plot(x, y, marker='o')
    plt.title('Numbers 1 through 10')
    plt.xlabel('Index')
    plt.ylabel('Value')
    plt.grid(True)
    plt.savefig('simple_line_plot.svg')
    plt.show()
    ```

    [After running the code and confirming file creation]

    <div class="generated_image">
      <img src="/data/simple_line_plot.svg" />
    </div>

    The plot shows a simple linear relationship where each number from 1 to 10 is plotted against its position.

    ### Mathematical Notation Guidelines:

    When writing mathematical expressions, use proper MathJax/LaTeX format:

    **For inline expressions:** Use single dollar signs `$...$`
    - Example: `$a^2 + b^2 = c^2$`
    - Example: `$\\frac{1}{2}$`
    - Example: `$\\sqrt{x}$`

    **For block expressions:** Use double dollar signs `$$...$$`
    - Example: `$$\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}$$`
    - Example: `$$\\begin{align} x &= y + z \\\\ &= 2z \\end{align}$$`

    **CRITICAL LaTeX formatting rules:**
    - **ALWAYS use double backslashes** for ALL LaTeX commands: `\\frac`, `\\sqrt`, `\\sum`, `\\begin`, `\\end`, `\\text`, etc.
    - Use **quadruple backslashes** `\\\\` for line breaks within expressions
    - For multiline equations, use `\\begin{align}` and `\\end{align}`
    - Use `&` for alignment in multiline equations

    **Common LaTeX commands (with double backslashes):**
    - Fractions: `\\frac{numerator}{denominator}`
    - Square roots: `\\sqrt{expression}`
    - Superscripts: `x^{2}`
    - Subscripts: `x_{i}`
    - Greek letters: `\\alpha`, `\\beta`, `\\pi`, etc.
    - Text in math: `\\text{your text here}`
    - Begin/end: `\\begin{align}` and `\\end{align}`

    **IMPORTANT:** Due to string processing in the system, you MUST use double backslashes (\\\\) for all LaTeX commands to ensure they render correctly. Single backslashes will be stripped during processing.

    **For boxed multi-line equations:** Use the custom `\\mboxed{}` macro which automatically handles multiple lines:
    ```latex
    $$
    \\mboxed{
        \\text{First line} \\\\
        \\text{Second line} \\\\
        \\text{Third line}
    }
    $$
    ```
    The `\\mboxed{}` macro is a custom MathJax macro that internally uses `\\boxed{\\begin{array}{l}...\\end{array}}` for proper multi-line support.

    ### Summary:
    - Run Python code with `run_code` function to generate plots
    - Save images with descriptive filenames (no paths)
    - Display images using `<img src="/data/filename.ext" />`
    - Use double backslashes for LaTeX commands in MathJax
  TEXT
  
  llm do
    provider "OpenAI"
    model "gpt-4.1"
    temperature 0.0
    presence_penalty 0.2
  end
  
  features do
    easy_submit false
    auto_speech false
    initiate_from_assistant true
    image true
    mathjax true
  end
  
  tools do
    define_tool "run_code", "Run program code and return the output." do
      parameter :command, "string", "Program that execute the code (e.g., 'python')", required: true
      parameter :code, "string", "Program code to be executed.", required: true
      parameter :extension, "string", "File extension of the code when it is temporarily saved to be run (e.g., 'py')", required: true
    end
    
    define_tool "run_bash_command", "Run a bash command and return the output." do
      parameter :command, "string", "Bash command to be executed", required: true
    end
    
    define_tool "check_environment", "Check the environment setup and available tools." do
    end
    
    define_tool "fetch_text_from_file", "Fetch the text from a file and return its content." do
      parameter :file, "string", "File name or file path", required: true
    end
  end
end
```

</details>

## ツール定義を含むアプリ

アプリは会話中にAIエージェントが使用できるツールを定義できます。ツールはファサードパターンを使用して、別の`*_tools.rb`ファイルに実装されます。

### ツール付きMDSL例
```ruby
app "WikipediaOpenAI" do
  description "Wikipedia記事を検索・取得"
  icon "fa-globe"
  
  tools do
    define_tool "search_wikipedia", "Wikipediaで記事を検索" do
      parameter :query, "string", "検索クエリ", required: true
      parameter :lang, "string", "言語コード（デフォルト: ja）"
    end
  end
end
```

### ツール実装
対応する`wikipedia_tools.rb`ファイルを作成：

```ruby
module WikipediaTools
  def search_wikipedia(query:, lang: "ja")
    # 実装をここに記述
  end
end

class WikipediaOpenAI < MonadicApp
  include WikipediaTools
end
```

<details>
<summary>完全な実装例</summary>

```ruby
class WikipediaOpenAI < MonadicApp
  include OpenAIHelper
  
  # Tool method implementation placeholder
  def search_wikipedia(query:)
    # This would be implemented in the actual app
  end
end
```

</details>

## Monadicモードを使用するアプリ

Monadicモードを使用すると、アプリは会話を通じて構造化されたコンテキストを維持できます。これは現在、信頼性の高い構造化出力機能のため、主にOpenAIモデルでサポートされています。

### 重要なポイント：
- OpenAIプロバイダーでのみ有効化
- `monadic`と`toggle`機能を両方有効にしない
- JSON形式のレスポンスが必要

<details>
<summary>例：Novel Writer（novel_writer_openai.mdsl）</summary>

```ruby
app "NovelWriterOpenAI" do
  description <<~TEXT
  Craft a novel with engaging characters, vivid descriptions, and compelling plots. Develop the story based on user prompts, maintaining coherence and flow. <a href="https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps?id=novel-writer" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT
  icon "book"
  
  system_prompt <<~TEXT
    You are a skilled and imaginative author tasked with writing a novel. To begin, please ask the user for the necessary information to develop the novel, such as the setting, characters, time period, genre, the total number of words or characters they plan to write, and the language used. Once you have this information, start crafting the story.

    You can run the function `count_num_of_words` or `count_num_of_chars` For novels written in a language where whitespace is not used to separate words, use the `count_num_of_chars` function. Otherwise, use the `count_num_of_words` function. The argument for these functions is the text you want to count. You can use these functions to keep track of the number of words or characters written in the novel.

    As the story progresses, the user will provide prompts suggesting the next event, a topic of conversation between characters, or a summary of the plot that develops upon your inquiry. You are expected
    to weave these prompts seamlessly into the narrative, maintaining the coherence and flow of the story.

    Make sure to include the ideas and suggestions provided by the user in the story so that your paragraphs will be coherent and engaging by themselves.

    Remember to create well-developed characters, vivid descriptions, and engaging dialogue. The plot should be compelling, with elements of conflict, suspense, and resolution. Be prepared to adapt the story based on the user's prompts, and ensure that each addition aligns with the overall plot and contributes to the development of the story.

    Your response is structured in a JSON object. Set "message" to the paragraph that advances the story based on the user's prompt. The contents of the "context" are instructed below.

    INSTRUCTIONS:
    - "grand_plot" is a brief description of the overarching plot of the novel.
    - "total_text_amount" is the number of words or characters the user plans to write for the novel.
    - "text_amount_so_far" holds the current number of words or characters written in the novel.
    - "language" is the language used in the novel.
    - "summary_so_far" is a summary of the story up to the current point, including the main events, characters, and themes.
    - "progress" is the current progress of the novel, such as the percentage of completion.
    - "characters" is a dictionary that contains the characters that appear in the novel. Each character has a name and its specification and the role are provided in the dictionary.
    - "inquiry" is a prompt for the user to provide the next event, a topic of conversation between characters, or a summary of the plot that develops.

    Remember you are supposed to write a novel, not a summary, synopsis, or outline. It is not a good idea to let the plot move too fast. Stick to the good old rule of "show, don't tell."
  TEXT
  
  llm do
    provider "openai"
    model "gpt-4.1"
    temperature 0.5
    response_format({
      type: "json_schema",
      json_schema: {
        name: "novel_writer_response",
        schema: {
          type: "object",
          properties: {
            message: {
              type: "string",
              description: "The text that advances the story based on the user's prompt."
            },
            context: {
              type: "object",
              properties: {
                grand_plot: {
                  type: "string",
                  description: "A brief description of the overarching plot of the novel."
                },
                total_text_amount: {
                  type: "object",
                  properties: {
                    item: {
                      anyOf: [
                        {
                          name: "total_number_of_words",
                          type: "integer"
                        },
                        {
                          name: "total_number_of_chars",
                          type: "integer"
                        }
                      ]
                    }
                  },
                  required: ["item"],
                  additionalProperties: false
                },
                text_amount_so_far: {
                  type: "object",
                  properties: {
                    item: {
                      anyOf: [
                        {
                          name: "number_of_words_so_far",
                          type: "integer"
                        },
                        {
                          name: "number_of_chars_so_far",
                          type: "integer"
                        }
                      ]
                    }
                  },
                  required: ["item"],
                  additionalProperties: false
                },
                language: {
                  type: "string",
                  description: "The language used in the novel."
                },
                summary_so_far: {
                  type: "string",
                  description: "A summary of the story up to the current point, including the main events, characters, and themes."
                },
                characters: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      name: {
                        type: "string",
                        description: "The name of the character."
                      },
                      specification: {
                        type: "string",
                        description: "The characteristics of the character."
                      },
                      role: {
                        type: "string",
                        description: "The role of the character in the novel."
                      }
                    },
                    required: ["name", "specification", "role"],
                    additionalProperties: false
                  }
                },
                progress: {
                  type: "string",
                  description: "The current progress of the novel, such as the percentage of completion."
                },
                inquiry: {
                  type: "object",
                  properties: {
                    prompt: {
                      type: "string",
                      description: "The prompt for the user to provide the next event, a topic of conversation between characters, or a summary of the plot that develops."
                    },
                    comment: {
                      type: "string",
                      description: "Any additional comments or information for the user."
                    }
                  },
                  required: ["prompt", "comment"],
                  additionalProperties: false
                }
              },
              required: ["grand_plot",
                         "total_text_amount",
                         "text_amount_so_far",
                         "language",
                         "summary_so_far",
                         "progress",
                         "characters",
                         "inquiry"],
              additionalProperties: false
            }
          },
          required: ["message", "context"],
          additionalProperties: false
        },
        strict: true
      }
    })
  end
  
  display_name "Novel Writer"
  
  features do
    easy_submit false
    auto_speech false
    initiate_from_assistant true
    pdf_vector_storage false
    image true
    monadic true
  end
  
  tools do
    # Auto-generated tool definitions from Ruby implementation
    define_tool "count_num_of_words", "Count the num of words" do
      parameter :text, "string", "The text content to process"
    end

    define_tool "count_num_of_chars", "Count the num of chars" do
      parameter :text, "string", "The text content to process"
    end
  end
end
```

</details>

## 複数のAIプロバイダーを使用するアプリ

一部のアプリは、ツール内で異なるAIプロバイダーにアクセスできます。Second Opinionアプリは、2段階の相談プロセスを実装する良い例です。

### 2段階プロセス：
1. **初回意見**: 自動検証なしの最初のAI応答
2. **セカンドオピニオン**: ユーザーが開始する任意のプロバイダーからの検証

<details>
<summary>例：Second Opinion（second_opinion_openai.mdsl）</summary>

```ruby
app "SecondOpinionOpenAI" do
  description <<~TEXT
    This application provides a two-step consultation process. First, the AI agent gives its initial response to your question. Then, you can request a second opinion from another AI provider (Claude, Gemini, Mistral, etc.) to verify or provide alternative perspectives on the answer. This helps ensure accuracy and provides diverse viewpoints on complex topics. <a href="https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps?id=second-opinion" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT
  
  icon "fa-solid fa-people-arrows"
  
  display_name "Second Opinion"
  
  # Include the SecondOpinionAgent module for tool implementation
  include_modules "SecondOpinionAgent"
  
  llm do
    provider "openai"
    model "gpt-4.1"
    temperature 0.2
  end

  system_prompt <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are capable of answering various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user.

      ## Two-Step Process:
      1. **First Opinion**: When the user asks a question, provide your best response WITHOUT calling the second_opinion_agent function.
      2. **Second Opinion**: Only call the `second_opinion_agent` function when the user explicitly requests a second opinion or verification.

      ## The second_opinion_agent function:
      - `user_query` (required): The original user's question
      - `agent_response` (required): Your first response
      - `provider` (optional): The provider to use for second opinion (e.g., 'claude', 'gemini', 'mistral')
      - `model` (optional): Specific model to use

      ## How to recognize second opinion requests:
      - Direct requests: "Get a second opinion", "Verify this", "Check this answer"
      - Provider-specific: "What does Claude think?", "Ask Gemini", "Get Mistral's opinion"
      - Validation requests: "Is this correct?", "Double-check this", "Confirm this"

      ## Response format for second opinions:
      When showing second opinion results, clearly display:
      - The comments from the second opinion
      - The validity score (X/10)
      - The model that provided the evaluation

      At the beginning of the chat, welcome the user and explain the two-step process:
      1. You'll first provide your answer
      2. They can then request a second opinion from any available provider
      3. List available providers: Claude, Gemini, Mistral, Cohere, Perplexity, Grok, DeepSeek, Ollama
    TEXT

  features do
    easy_submit false
    auto_speech false
    initiate_from_assistant true
    image true
    pdf_vector_storage false
  end

  tools do
    # Standard tools will be auto-completed from MonadicApp base class
    
    define_tool "second_opinion_agent", "Verify the response before returning it to the user" do
      parameter :user_query, "string", "The query given by the user", required: true
      parameter :agent_response, "string", "Your response to be verified", required: true
      parameter :provider, "string", "Provider name (e.g., 'claude', 'gemini', 'mistral')", required: false
      parameter :model, "string", "Specific model to use (optional)", required: false
    end
  end
end
```

</details>

## 標準ツール実装

多くの一般的なツールは`lib/monadic/app.rb`にすでに実装されており、アプリ固有の実装は不要です：

- `current_time` - 現在のタイムスタンプを返す
- `run_code`、`run_bash_command` - コード実行
- `fetch_text_from_*` - ファイルコンテンツの抽出
- `analyze_image`、`analyze_audio`、`analyze_video` - メディア分析

## ベストプラクティス

1. **ファサードパターンを使用**: ツールは`*_tools.rb`ファイルに定義
2. **命名規則に従う**: アプリ名はクラス名と一致させる
3. **プロバイダーサフィックスを含める**: 例：`ChatOpenAI`、`CodeInterpreterGemini`
4. **ツールを集中させる**: 各ツールは1つのことをうまく実行
5. **エラーを適切に処理**: 常に入力を検証し、役立つエラーメッセージを提供

## トラブルシューティング

- **空のツールブロック**: 標準ツールのみを使用する場合でも、空の`tools do end`ブロックを含める
- **メニューグループ化の問題**: アプリ名がクラス名と正確に一致することを確認
- **モデルが見つからない**: ヘルパーの`list_models`が`$MODELS`キャッシュを使用していることを確認
- **ツールが見つからない**: `*_tools.rb`ファイルが存在し、モジュールがインクルードされていることを確認

## 関連項目

- [アプリの開発](./develop_apps.md) - アプリ開発の詳細ガイド
- [Monadic DSL](./monadic_dsl.md) - 完全なMDSL構文リファレンス
- [Monadicモード](./monadic-mode.md) - 構造化コンテキストの理解
- [Dockerコンテナの追加](./adding-containers.md) - カスタムコンテナでの拡張