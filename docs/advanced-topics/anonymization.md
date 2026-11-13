# Anonymization

## Overview

**Anonymize** replaces the words you choose (names, organizations, addresses and the like) with placeholders such as `<<PERSON_1>>` in the text a chat sends to AI providers. Replies come back with the words put back, so you read and write the conversation as usual.

Each chat keeps its own list of words to hide. Names are found by the Privacy container, which runs on this computer; you decide which words are hidden.

## Hiding Words :id=hiding-words

1. Write your message, then click **Anonymize** beside the message box.
2. The panel **Words to hide in this chat** shows the message with the names found in it highlighted, and lists them with their types. To leave a word as it is, click **×** (**Do not hide**) beside it; to change its type, choose another in its menu.
3. To add a word that was not found, select it in the text of the panel, choose its type, and click **Hide selected words**.
4. Click **Hide these words**, then send the message.

A word is hidden wherever it occurs in the chat. The status beside the message box shows how many words are hidden (**Hidden: n**); click it to open the panel again, change a word's type, or stop hiding a word. A word you chose not to hide is listed under **Not hidden:** and is not offered again; click it (**Offer this word again**) to put it back.

A change applies to what the chat sends from then on.

!> **What is anonymized.** Only text the app sends for the chat. Images, screen contents, file contents, files and pages that code execution or the browser reads, your voice (voice input sends the recording as it is to the speech-to-text service), names not in the list, and what was sent before a word was hidden are not covered. The chat history, the logs and a **Restored** export keep the original words. Anonymization makes the provider see placeholders instead of the listed words; it does not make a conversation safe to share.

## Where the Words Are Hidden

The words are hidden in what a chat sends:

- the chat's own requests to its model, including earlier messages and tool results
- second opinions, **Verify**, AI User suggestions and title suggestions
- the results of the Knowledge Base search, as they go to the model
- text read aloud (a hidden word is read as its type and number, such as "PERSON 1")
- the names of the files the chat has made, as the AI is told of them (the tools that read a file get the real name back)

What the AI is told about the [work screen](../basic-usage/web-interface.md#work-screen), and the text it looks at there, are checked instead: when they hold a hidden word, they are not sent.

Before a request leaves, it is checked once more; a request that still holds a hidden word in a part that is not replaced (such as the system prompt or a tool definition) is not sent, and an error says so. A system message that holds a hidden word is refused when you write it.

A chat whose list cannot be read (for example after the server was restarted) sends nothing until you open it again from the [chat history](../basic-usage/web-interface.md#chat-history-panel).

## Voice and Live Conversation

Voice input works in a chat that hides words, but the voice itself is not hidden. Live Conversation (speech-to-speech) sends the conversation as it is, so it is not available in a chat that hides words.

## Knowledge Base :id=knowledge-base

A chat that hides words cannot be saved to the Knowledge Base: the Knowledge Base would keep the words, and a search from another chat would send them. Use **Export** to keep such a chat.

## Export and Import :id=export

The **Export** button opens a dialog with two independent choices:

- **Encryption**: encrypt the file with AES-256-GCM (Argon2id key derivation) using a passphrase you provide. Passphrases need at least 8 characters, and the confirmation must match.
- **Content** (shown for a chat that hides words): **Restored** writes the conversation with the original words and the chat's list of words, so an imported chat goes on hiding them. **Masked** writes the conversation with the hidden words replaced by their placeholders everywhere in the file, and holds neither the original words nor the list.

For a chat that hides words the dialog starts with **Masked**. Choosing **Restored** without encryption shows a warning, and the file name ends in `-PRIVATE`.

To open an export, use **Import** (and the passphrase for an encrypted file). A file from an earlier version that carries words marked for hiding is read into the chat's list; the page says how many, and you can check them in the panel. In new messages, `⟦` and `⟧` are ordinary characters.

## Document DB Export and Import (Actions menu) :id=document-db-export-import

The **Actions → Export Document DB** and **Actions → Import Document DB** menu items operate on the entire qdrant volume — every conversation saved to the Knowledge Base, every PDF, and every other Knowledge Base entry. The [chat history](../basic-usage/web-interface.md#chat-history-panel) is not part of it. Both items show a confirmation dialog before proceeding.

For export, you can choose between:

- **Encrypt and Export** (default): prompts for a passphrase, encrypts the tarball with AES-256-GCM (PBKDF2-SHA256, 600 000 iterations) over a per-export salt, and writes `monadic-qdrant.tar.gz.enc` to the shared folder. The plaintext tarball is removed after a successful encryption pass.
- **Export Plain**: writes the unencrypted tarball directly. The dialog warns that the file contains every conversation saved to the Knowledge Base and every PDF in plaintext.

Import detects the file extension automatically: `.tar.gz` is unpacked directly; `.tar.gz.enc` prompts for the passphrase, decrypts to a temporary plaintext file, runs the qdrant volume import, and removes the temporary file. A wrong passphrase or tampered ciphertext fails decryption (the tarball is never partially unpacked) and the qdrant volume is left untouched.

Encryption format: `[magic 'MQDB'] [version 0x01] [salt 16] [iv 12] [ciphertext] [authTag 16]`, streaming-friendly so multi-GB volumes do not need to fit in memory.

## Finding Names :id=finding-names

Names are found by the Privacy container (Microsoft Presidio with spaCy models), which runs on this computer and starts with Monadic Chat. When it is not running, **Anonymize** starts it and says that the name finder is starting; try again in a moment. You can always select words yourself in the panel.

The finder reads the message in the sidebar's conversation language, or, with **Automatic**, in the language it detects. English is always available. To find names in other languages, open **Actions → Install Options** and turn them on under **Name Finder — Additional Languages** (German, Spanish, French, Italian, Japanese, Dutch, Portuguese, Chinese); the change applies when you save, without a rebuild.

The finder does not find every name. In Japanese, a name of 2 to 12 kanji or katakana followed by an honorific (さん, 様, 氏, 先生, くん, 君, ちゃん, 殿) is found whole, in addition to what the language model finds; names written in hiragana, names with no honorific and uncommon names may be missed. Add such words yourself.

## Configuration Reference

Settings stored in `~/monadic/config/env`:

| Variable | Values | Default | Description |
|---|---|---|---|
| `PRIVACY_FILTER` | `true` / `false` | `true` | Set to `false` to not download or start the Privacy container. Names are then not found automatically; you can still select words yourself. |
| `PRIVACY_LANGS` | comma-separated language codes | `en` | Languages the Privacy container loads. When you save in **Actions → Install Options**, English is added automatically; if you edit the file directly, include `en`. Supported codes: `en`, `de`, `es`, `fr`, `it`, `ja`, `nl`, `pt`, `zh`. |
| `PRIVACY_DEV_PORT` | port number | `8001` | Used in development mode only, to reach the Privacy container from the host. |

After editing `PRIVACY_FILTER` or `PRIVACY_LANGS` in the file directly, restart Monadic Chat.

## Custom Apps

A `privacy do` block in an app's MDSL has no effect, and the server prints a warning when the app is loaded. Remove it. An app without `library_save false` and `library_search false` in its `features` block can save to and search the Knowledge Base.
