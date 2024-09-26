# Monadic Mode

Monadic Mode is a distinctive feature of Monadic Chat. In Monadic Mode, you can maintain and update the context of the conversation, referencing it as you chat.  This allows for more meaningful and coherent interactions with the AI agent.

![Monadic Chat Architecture](/assets/images/monadic-messaging.svg ':size=200')

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

### Example of Novel Writer

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

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

### Example of Language Practice Plus

Language learning benefits significantly from conversational practice.  Ideally, these conversations should flow naturally and adapt to the context. However, using a foreign language fluently can be challenging, and learners often make mistakes or struggle to find the right expressions.  The Language Practice Plus app uses Monadic Mode to provide linguistic feedback and suggestions during the conversation, making practice more effective.

The app maintains the following structure within its `context`:

* `message` (string): The AI's response in the target language.
* `context` (hash): Contains the following:
    * `target_language` (string): The language being practiced.
    * `advice` (array): An array of linguistic advice and suggestions related to the user's input.

While the `context` here might deviate slightly from the typical definition, it provides valuable information beyond simple exchanges, enhancing the learning process.  The AI agent can offer corrections, alternative expressions, and other helpful tips, directly within the context of the conversation.  This makes the interaction more purposeful and helps learners improve their language skills more efficiently.


<details>
<summary>Recipe File (language_practice_plus_app.rb)</summary>

![](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/ruby/apps/language_practice_plus/language_practice_plus_app.rb ':include :type=code')

</details>
