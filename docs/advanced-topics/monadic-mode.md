# Monadic Mode

?> This document has not yet been updated to the new MDSL format. For more information on the MDSL format, please refer to [Monadic DSL](./monadic_dsl.md). An update is planned soon.

Monadic Mode is a distinctive feature of Monadic Chat. In Monadic Mode, you can maintain and update the context of the conversation, referencing it as you chat.  This allows for more meaningful and coherent interactions with the AI agent.

## Basic Structure

In Monadic Mode, each query to the language model generates an object with the following structure. This structure allows the conversation's context to be preserved and updated throughout the interaction. The `message` field contains the AI agent's response, similar to a regular chat. The `context` field stores information accumulated from previous exchanges or information shared behind the scenes.

```json
{
  "message": "Hello, world!",
  "context": {
    "key1": "value1",
    "key2": "value2"
  }
}
```

During a conversation, both computers and humans do more than just exchange vocalized or written messages.  There's an underlying context and purpose, constantly referenced and updated as the dialogue progresses.  While humans manage this context naturally, Monadic Mode provides a structured way to achieve this with AI agents. By predefining the format and structure of this "meta-information," conversations become more focused and purposeful.

## Specific Examples

### Example of Jupyter Notebook app

One of the unique features of Monadic Chat is the ability to access a Linux environment on Docker, enabling file sharing with the host computer. This capability is leveraged in the Jupyter Notebook app, where the AI agent can suggest Python code to the user. Users can provide data through a shared folder and receive result files from executing the code.

In the Jupyter Notebook app, code is executed cell by cell, and variables or functions defined in one cell can be referenced in subsequent cells. Therefore, when requesting code suggestions from the AI agent, it's essential to reference previously defined variables and functions while proposing new code. It's also crucial to know which libraries or modules are currently imported. Additionally, the notebook's filename (URL) must be stored.

The Jupyter Notebook app maintains the following information as an object, updating the components to use as the context for the next response:

* `message` (string)
* `context` (hash)
    * `link` (the url of the notebook, string)
    * `modules` (the imported libraries, array)
    * `functions` (the functions defined with the function name and arguments, array)
    * `variables` (the variables defined, array)

If more detailed information about defined variables or functions is needed, the source code of the notebook is read. The AI agent can also verify which programs or libraries are available in the current execution environment.

<details>
<summary>Recipe File (jupyter_notebook_openai.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/jupyter_notebook/jupyter_notebook_openai.rb ':include :type=code')

</details>

### Example of Novel Writer app

The Novel Writer app uses Monadic Mode to facilitate collaborative novel writing.  Maintaining consistency in characters, plot, setting, and other details is crucial throughout the writing process.  The Novel Writer app uses the following structure within the `context` object:

* `message` (string): The generated text for the current step in the story.
* `context` (hash):  Contains the following key-value pairs:
    * `plot` (string): The overall plot of the story.
    * `target_length` (int): The target word count for the novel.
    * `current_length` (int): The current word count.
    * `language` (string): The language being used.
    * `summary` (string): A summary of the story so far.
    * `characters` (array): An array of characters in the story.
    * `question` (string): A question or prompt to guide the next step in the story.

The conversation progresses through user prompts and AI responses. The user provides instructions about the story's development, and the AI agent generates text based on those instructions, updating the `message` and `context` fields accordingly. The user then uses the generated text and the `question` prompt to guide their next input.

<details>
<summary>Recipe File (novel_writer_app.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

### Example of Language Practice Plus app

Language learning benefits significantly from conversational practice.  Ideally, these conversations should flow naturally and adapt to the context. However, using a foreign language fluently can be challenging, and learners often make mistakes or struggle to find the right expressions.  The Language Practice Plus app uses Monadic Mode to provide linguistic feedback and suggestions during the conversation, making practice more effective.

The app maintains the following structure within its `context`:

* `message` (string): The AI's response in the target language.
* `context` (hash): Contains the following:
    * `target_language` (string): The language being practiced.
    * `advice` (array): An array of linguistic advice and suggestions related to the user's input.

While the `context` here might deviate slightly from the typical definition, it provides valuable information beyond simple exchanges, enhancing the learning process.  The AI agent can offer corrections, alternative expressions, and other helpful tips, directly within the context of the conversation.  This makes the interaction more purposeful and helps learners improve their language skills more efficiently.


<details>
<summary>Recipe File (language_practice_plus_app.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/language_practice_plus/language_practice_plus_app.rb ':include :type=code')

</details>
