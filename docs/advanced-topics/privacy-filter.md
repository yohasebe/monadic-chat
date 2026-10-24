# Privacy Filter (PII Masking)

## Overview

The Privacy Filter masks personally identifiable information (PII) in user messages before they are sent to AI providers, then restores the original values in the AI's response on the way back. Detection runs locally in a separate Docker container (Microsoft Presidio + spaCy) so PII never leaves your machine on its way to or from the LLM.

The Privacy container is part of Monadic Chat's default container set, so the feature is ready to use the first time you start the app. Masking is turned on per conversation with the toggle in each app.

## When to Use It

- Drafting emails or documents that mention real names, email addresses, or phone numbers.
- Translating text that contains personal information.
- Sharing snippets that include sensitive identifiers without rewriting them by hand.

## Installation

The Privacy container is downloaded as a prebuilt image and starts with the rest of Monadic Chat. All supported language models are included in the image; English is always enabled.

To enable masking for non-English content, turn on additional languages:

1. Open **Actions → Install Options**.
2. Locate the **Privacy Filter — Additional Languages** section.
3. Check the languages you want from German (de), Spanish (es), French (fr), Italian (it), Japanese (ja), Dutch (nl), Portuguese (pt), Chinese (zh). English is always present and cannot be unchecked.
4. Click **Save**. No rebuild is involved — a running Privacy container is restarted with the new language set automatically. If the Monadic Chat server is currently running, restart it (Stop/Start) so the per-session toggle recognizes the newly enabled languages.

Language selection is a runtime setting: enabling or disabling a language changes which models the server loads, not the container image.

Runtime opt-out: set `PRIVACY_FILTER=false` in `~/monadic/config/env` to skip the Privacy container entirely. The toggle becomes disabled with the tooltip "Privacy Filter is disabled." until the env value is restored.

## Per-Session Toggle

Apps that support privacy filtering show a **Privacy Filter** toggle in the Session Controls panel.

- Turn it on before clicking **Start Session** to enable masking for the session.
- The toggle locks when the session starts. Pressing **Reset** or switching to a different app re-enables editing, for a new chat. To use the filter after the session has started, press **Reset**.
- A chat whose toggle is on when the session starts is Private: it is not kept in the [chat history](../basic-usage/web-interface.md#chat-history-panel). A chat stays Private when the filter could not be started; turn the toggle off before **Start Session** for a normal chat. The messages of a Private chat are still sent to the model; they are masked only while the filter is on.
- Your last choice is remembered per app: the toggle starts in that state (off until you first turn it on).

When the toggle is disabled, hovering over it shows the reason:

- *This app does not support Privacy Filter.* — The app's MDSL does not declare a `privacy` block.
- *Privacy Filter is disabled.* — `PRIVACY_FILTER=false` is set in the environment, so the Privacy container was not started.
- *Privacy Filter is not installed for this language. Install via Settings → Install Options.* — The sidebar's conversation_language is not among the enabled languages. Enable the language in Actions → Install Options (applies on save), or change the conversation_language to one that is enabled.

## Language Selection

The session toggle's enabled state and the masking language follow the sidebar **conversation_language**:

| Sidebar conversation_language | Masking language | Toggle |
|---|---|---|
| Automatic | Detected from your messages (English until detected) | enabled |
| English (en) | English | enabled |
| An installed non-English language (e.g. ja, de, fr) | That language (matching spaCy NER model) | enabled |
| An uninstalled language (e.g. Korean) | — | disabled with tooltip |

With **Automatic**, the masking language is English until a message is detected reliably as one of the enabled languages; from then on the session uses that language. When masking non-English content, set the conversation_language explicitly in the sidebar, so the first messages are masked in that language too.

Japanese has additional dedicated handling: when `lang_used` is `ja`, the Privacy container trims trailing honorifics (`さん`, `様`, `先生`, `君`, etc.) from PERSON spans so that placeholders capture only the actual name.

## Indicator and Registry

When the filter is active, the chat header shows an indicator:

- **Privacy ready** (gray unlock icon): the filter is on but no entities have been masked yet.
- **Privacy ON (N)** (green lock icon with count): N placeholders are currently registered for restoration.
- **Privacy error** (red): the privacy container could not be reached. Check that Docker is running and the container is healthy.

If the privacy container is not running, it is started when an app that uses the filter is chosen. Loading its language models takes a while (about a minute the first time). If the filter is turned on before the container is ready, the toggle stays off and a notice says the filter is starting; turn it on again in a moment. When the container does not come up, a notice says so.

When the conversation_language is **Automatic**, a small language badge (with a language icon and, for example, **ja**) appears next to the indicator once the session has settled on a language. It does not appear for a language selected in the sidebar.

Clicking the indicator opens the **Privacy Registry**, which lists each placeholder, the original value, and the entity type (PERSON, EMAIL_ADDRESS, and so on), with a button to export the conversation. The registry is held in session memory only; it is never written to the conversation log on disk.

## Unmask Highlight

Conversation cards (both user input and assistant replies) underline every value that the Privacy Filter is currently tracking. The same placeholder always uses the same color — for example, every occurrence of the same person's name draws the same blue underline across every card, while a different name uses a different color. The background stays gray; only the underline color changes, so the layout is not visually busy.

Hover any underlined value to see the placeholder it travelled through (for example, *Tracked as <<PERSON_1>>*). The underline is applied after markdown rendering. It skips `<code>` and `<pre>` blocks; in links, only the link text is underlined and the link itself is not changed.

The highlight is purely visual; it never changes the LLM payload. The same value passes through the registry-aware masking pipeline whether or not it is highlighted.

## What Gets Masked

By default the filter masks the following entity types:

`PERSON`, `ORGANIZATION`, `EMAIL_ADDRESS`, `URL`, `POSTAL_CODE`, `PHONE_NUMBER`, `CREDIT_CARD`, `IP_ADDRESS`, `IBAN_CODE`, `US_SSN`, `US_MEDICAL_LICENSE`.

`LOCATION` ("Tokyo") is not in the default set, and `DATE_TIME` ("Friday") is not masked, so everyday phrasing stays as written.

App authors can adjust the entity list in MDSL:

```ruby
privacy do
  enabled true
  mask_types [:person, :email, :address]  # :address adds LOCATION
end
```

The allowed values are `:person`, `:organization`, `:email`, `:url`, `:address`, `:postal_code`, `:phone`, `:credit_card`, `:ip`, `:iban`, `:us_ssn` and `:medical_license`. The `privacy` block also accepts `score_threshold` (the detection confidence needed to mask, 0 to 1, default 0.4), `honorific_trim` (trim Japanese honorifics from names, default on) and `on_failure` (what happens when masking fails: `:block`, the default, does not send the message; `:pass` sends it unmasked, except when the conversation has marked words).

## Marking Words to Mask :id=marking-words

Names and other words the detection does not recognize can be marked by you. Select the words in the message box and click **Mask** below it (or press Ctrl/Cmd+Shift+K); the menu next to the button marks them as an organization, a place, an email address, a phone number, a URL or a date instead of a person. The words are wrapped as `⟦Edogawa Imataro⟧`, or `⟦Acme Inc.|organization⟧` with a type; you can also type the brackets yourself.

When the message is sent, the marks are taken out (the conversation shows the text as you wrote it) and the words are kept for the conversation:

- They are masked before the message is sent, and wherever they occur afterwards in the conversation, also when they are not marked again.
- They are masked in the messages and tool results sent to a model for the conversation, and in what is sent on its behalf (second opinions, Verify, AI User, the Session Context extraction); they are replaced in speech, and Live Conversation (speech-to-speech) stays unavailable while words are marked.
- When a marked word is also in a part of a request that is not masked (the system prompt, a tool definition, the app's settings), nothing is sent and an error says so. The check finds the word inside other words too, so marking a short or common word (such as "auto", "query" or "user", which the app's settings and tools use) stops the conversation; press Reset to remove the marks.
- Attached images, PDFs and audio are sent as they are: their contents are not checked for marked words.
- While words are marked, nothing is sent for the conversation with the Privacy Filter off: turn it back on, or press Reset to end the conversation (Reset forgets the marked words).
- Words marked in your own messages in an imported conversation file are read the same way (a file exported by Monadic Chat has its marks taken out already, so brackets in it stay as written).
- While a conversation has marked words, every request the Monadic Chat server sends to an outside service for that conversation is checked last, as it is sent, and is not sent if it holds one of them. The check reads the request's address, its text (a JSON body, a form, the text fields and file names of an upload) and the text messages of a speech connection. This covers what is sent on the conversation's behalf too: the tools (web search, image generation, speech) and the MCP server when the conversation uses it. Each conversation is checked for its own words only; requests that belong to no conversation (such as the MCP server used from another application) are not checked for marked words. Not checked: the contents of uploaded files and audio, programs the apps run on their own (scripts in the containers, code you run), and the services on this computer (such as a local model).
- A mark that cannot be read (not closed, nested, spanning lines, an unknown type) is refused, and the message is not sent. To write the brackets themselves, put a backslash before them: `\⟦`, `\⟧`.

Marked words need the current Privacy container; with an older one, a conversation with marked words is not sent until the container is updated.

A **Restored** export keeps the marked words, so an imported conversation goes on masking them. A **Masked** export masks them too and does not hold them; after importing such a file, mark the words again.

## Text-to-Speech (TTS) Sanitization

When the Privacy Filter is active, TTS playback (the per-card **Play** button, the Auto-Speech path, and the system **TTS** test) replaces tracked PII with the same short labels the streaming buffer uses (for example, "PERSON 1", "EMAIL ADDRESS 1"). This applies to every TTS provider — cloud TTS APIs (OpenAI, Gemini, ElevenLabs, etc.) never receive original names, addresses, or phone numbers, and listeners do not have to sit through long email addresses character-by-character.

The Web Speech API path (browser-native synthesis) goes through the same sanitizer. Even though the audio is produced locally, the text passed to the synth is identical to what a cloud provider would receive, keeping the UX consistent.

## Knowledge Base Save and Search

Apps that use the Privacy Filter do not save to the Knowledge Base; see [Privacy Filter and Knowledge Base by App](../basic-usage/basic-apps.md#privacy-kb-by-app) for the table. In those apps, and in apps that do not use the Knowledge Base, the Knowledge Base panel stays visible with its controls disabled, and a tooltip says why.

To preserve a conversation handled in a privacy-aware app, use **Privacy Export** (encryption + optional masked-only mode) — see the section below.

The Browse table shows a muted ⚠️ icon in front of an entry's title when the title or source contains something that looks like an email address or a phone number.

### `library_search` retrieval

When the Privacy Filter is active in a session that calls `library_search`, the retrieved snippets pass through the same Privacy Pipeline before they reach the LLM. Any PII present in the Knowledge Base is masked into placeholders for the request, and the LLM's reply is restored on the way back via the existing streaming-handler pass.

When the snippets cannot be masked (the privacy service is down), or a word you marked would still be in them, the results are withheld rather than sent unmasked.

### Global vs App-only scope

Saving a conversation as **Global** (rather than the default **App-only**) makes the entry retrievable from every app in this Monadic Chat install via `library_search`. The save dialog shows a warning when Global is selected, since apps you have not used yet can also retrieve the content. Prefer App-only unless the conversation is intentionally meant to be shared across apps.

## Encrypted Export

The **Export** button opens an export dialog:

- **Encryption** (always offered): encrypt the file with AES-256-GCM (Argon2id key derivation) using a passphrase you provide.
- **Content** (when the Privacy Filter has masked something in the session): export the conversation with the original values restored, or with the placeholders kept.

When Privacy is active in the session, the dialog defaults to **Masked** content so an accidental click does not write plaintext PII to disk. You can still pick **Restored** explicitly; that combination — Restored content with no encryption — triggers a red warning banner explaining what is about to land in the file. Files that end up containing plaintext PII are tagged with a `-PRIVATE` suffix in the filename so they are easy to spot in a downloads folder.

Common combinations:

1. **Encrypted + Restored** — a personal archive that can only be opened by you.
2. **Encrypted + Masked** — share analysis logs without exposing PII even after decryption.
3. **Plain + Masked** — quick sharable example with no real names.
4. **Plain + Restored** — flagged with `-PRIVATE` and the strongest warning; intended for trusted, local-only workflows.

Passphrase requirements: minimum 8 characters and the confirmation field must match. The strength meter is informational only and does not block submission.

To re-open an encrypted export, use the **Import** button and enter the passphrase when prompted. The registry is restored alongside the conversation so subsequent messages continue to mask consistently.

## Document DB Export and Import (Actions menu) :id=document-db-export-import

The **Actions → Export Document DB** and **Actions → Import Document DB** menu items operate on the entire qdrant volume — every saved conversation, PDF, and Knowledge Base entry. Both items show a confirmation dialog before proceeding.

For export, you can choose between:

- **Encrypt and Export** (default): prompts for a passphrase, encrypts the tarball with AES-256-GCM (PBKDF2-SHA256, 600 000 iterations) over a per-export salt, and writes `monadic-qdrant.tar.gz.enc` to the shared folder. The plaintext tarball is removed after a successful encryption pass.
- **Export Plain**: writes the unencrypted tarball directly. The dialog warns that the file contains every saved conversation and PDF in plaintext regardless of whether the Privacy Filter was active when each item was saved.

Import detects the file extension automatically: `.tar.gz` is unpacked directly; `.tar.gz.enc` prompts for the passphrase, decrypts to a temporary plaintext file, runs the qdrant volume import, and removes the temporary file. A wrong passphrase or tampered ciphertext fails decryption (the tarball is never partially unpacked) and the qdrant volume is left untouched.

Encryption format: `[magic 'MQDB'] [version 0x01] [salt 16] [iv 12] [ciphertext] [authTag 16]`, streaming-friendly so multi-GB volumes do not need to fit in memory.

## Supported Apps

The Privacy Filter is enabled in the MDSL definitions of these apps:

- Mail Composer
- Chat Plus
- Translate
- Second Opinion

Other apps do not declare `privacy do`, and the toggle stays disabled.

## Limitations

- Detection does not find every name. In Japanese, a name of 2 to 12 kanji or katakana followed by an honorific (さん, 様, 氏, 先生, くん, 君, ちゃん, 殿) is masked whole, in addition to what the language model finds; names written in hiragana, names with no honorific and uncommon names may be missed. Mark such words yourself (see [Marking Words to Mask](#marking-words)).
- Custom recognizers live in the privacy container source (`docker/services/privacy/recognizers/`). Adding new recognizers requires rebuilding the container (**Actions → Build Privacy Container**).
- Masking adds a small per-message latency, typically 50-200 ms depending on text length. Each turn re-masks the entire context (user and past assistant messages alike) so the registry stays consistent across turns.
- Masking supports the nine languages whose spaCy models are included in the privacy image: English, German, Spanish, French, Italian, Japanese, Dutch, Portuguese, Chinese. Languages outside this set (e.g. Korean, Arabic) cannot use the Privacy Filter — the session toggle is disabled when the sidebar conversation_language is one of them.

## Configuration Reference

Settings stored in `~/monadic/config/env`:

| Variable | Values | Default | Description |
|---|---|---|---|
| `PRIVACY_FILTER` | `true` / `false` | `true` | Runtime gate. Set to `false` to skip starting the privacy container at startup; the toggle becomes disabled until restored to `true`. |
| `PRIVACY_LANGS` | comma-separated language codes | `en` | Languages the privacy server loads at startup (all models are included in the image). When you save in Actions → Install Options → "Privacy Filter — Additional Languages", English is added automatically. If you edit the env file directly, include `en`. Supported codes: `en`, `de`, `es`, `fr`, `it`, `ja`, `nl`, `pt`, `zh`. |
| `PRIVACY_DEV_PORT` | port number | `8001` | Used in development mode only to expose the privacy container's HTTP port to the host. |

Changes to `PRIVACY_LANGS` made through Actions → Install Options apply on save (a running privacy container is restarted automatically). If you edit the env file directly, restart Monadic Chat so the new value takes effect. After changing `PRIVACY_FILTER`, restart Monadic Chat (no rebuild required).
