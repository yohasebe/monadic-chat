# Monadic Mode

Monadic Mode is a feature that allows you to maintain context in conversations with AI agents. With Monadic Mode, you can maintain and update context in a defined format while exchanging messages, and you can refer to it during the conversation.

## Basic Structure

In Monadic Mode, the context is maintained by generating an object with the following structure in each query to the language model. The `message` in the object corresponds to the message returned by the AI agent in a regular chat. The `context` holds information accumulated from previous interactions or information that should be shared behind the scenes.

```json
{
  "message": "Hello, world!",
  "context": {
    "key1": "value1",
    "key2": "value2"
  }
}
```

In both human and computer conversations, it's not just about exchanging messages that are vocalized or written as language expressions. There is always context and purpose behind the conversation, and the discourse progresses by constantly referencing and updating them.

In human-to-human conversations, this kind of context maintenance and reference happens naturally, but in conversations with AI agents, maintaining and referencing such context is also useful. By defining the format and structure of such "meta-information" in advance, it is expected that conversations with AI agents will become more purposeful.

## Specific Examples

### Example of Novel Writer

For instance, in the Novel Writer app, you can write a novel using Monadic Mode. When writing a novel, it is important to maintain consistent information such as characters, locations, and plot flow from beginning to end. Therefore, the Novel Writer app maintains information like the following as an object, and the updated components are used as the context for the next statement.

- Message (string)
- Context (hash)
  - Overall plot (string)
  - Target text length (int)
  - Current text length (int)
  - Language used (string)
  - Summary of current content (string)
  - Characters (array)
  - Questions for the next development (string)

The conversation progresses through interactions between the user and the AI agent. The user gives instructions to the AI agent regarding the development of the novel. Based on those instructions, the AI agent returns a new piece of text as a message and updates the context. The user refers to the text returned by the AI agent and the "questions" embedded in the context to give the next instructions.

In this way, Monadic Mode is characterized by maintaining "context" behind the exchange of messages between the user and the AI agent and making new statements while referencing it. By using Monadic Mode, it is possible to have a "discourse" that goes beyond a mere sequence of utterances.

<details>
<summary>Recipe File (novel_writer_app.rb)</summary>

![novel_writer_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/novel_writer/novel_writer_app.rb ':include :type=code')

</details>

### Example of Language Practice Plus

In language learning, practicing conversation in the target language is important. It is desirable for the content of the conversation to change according to the flow of the conversation at the moment rather than being predetermined. However, when having a conversation in a foreign language rather than in one's native language, it can be difficult to always use the optimal expressions. Therefore, if the AI agent can point out errors or suggest new expressions, more effective language practice becomes possible.

- Message (string)
- Context (hash)
  - Target language (string)
  - Advice (array)

Here, "context" may differ slightly from the general meaning of context, but when considering the purpose of the conversation practice process, it is very beneficial to obtain information that is not just "responses." Monadic Mode is a feature that can link conversations with AI agents to a realistic purpose.

<details>
<summary>Recipe File (language_practice_plus_app.rb)</summary>

![language_practice_plus_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/ruby/apps/language_practice_plus/language_practice_plus_app.rb ':include :type=code')

</details>
